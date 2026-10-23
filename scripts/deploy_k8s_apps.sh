#!/usr/bin/env bash
# ==============================================================================
# Script de déploiement des applications Kubernetes sur le cluster K3s OCI
# ==============================================================================

set -euo pipefail

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPS_DIR="${PROJECT_ROOT}/k8s/apps"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 1. Vérification de kubectl
command -v kubectl >/dev/null 2>&1 || {
    log_error "kubectl n'est pas installé ou introuvable dans le PATH."
    exit 1
}

# 2. Localisation du fichier kubeconfig
KUBECONFIG_PATH=""
if [ -n "${KUBECONFIG:-}" ] && [ -f "${KUBECONFIG}" ]; then
    KUBECONFIG_PATH="${KUBECONFIG}"
elif [ -f "${PROJECT_ROOT}/ansible/k3s-kubeconfig.yaml" ]; then
    KUBECONFIG_PATH="${PROJECT_ROOT}/ansible/k3s-kubeconfig.yaml"
elif [ -f "${PROJECT_ROOT}/k3s-kubeconfig.yaml" ]; then
    KUBECONFIG_PATH="${PROJECT_ROOT}/k3s-kubeconfig.yaml"
elif [ -f "${HOME}/.kube/config" ]; then
    KUBECONFIG_PATH="${HOME}/.kube/config"
fi

if [ -z "${KUBECONFIG_PATH}" ]; then
    log_error "Fichier k3s-kubeconfig.yaml introuvable."
    log_error "Exécutez le playbook Ansible ou téléchargez l'artefact du workflow GitHub Actions."
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
log_info "Utilisation du kubeconfig : ${CYAN}${KUBECONFIG}${NC}"

# 3. Vérification de la connectivité au cluster
log_info "Test de connectivité avec l'API Server K3s..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Impossible de joindre le cluster K3s avec le fichier ${KUBECONFIG_PATH}."
    exit 1
fi
log_success "Connectivité au cluster K3s validée."

# 4. Déploiement récursif des manifestes applicatifs
if [ ! -d "${APPS_DIR}" ]; then
    log_error "Le dossier des applications ${APPS_DIR} n'existe pas."
    exit 1
fi

log_info "Application des manifestes Kubernetes depuis ${APPS_DIR}..."
kubectl apply -R -f "${APPS_DIR}"

# 5. Attente du statut actif (Rollout) des déploiements
log_info "Attente de la disponibilité des pods applicatifs..."

DEPLOYMENTS=($(kubectl get deployments -A -l app.kubernetes.io/name -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{end}' 2>/dev/null || true))

if [ ${#DEPLOYMENTS[@]} -eq 0 ]; then
    # Fallback spécifique si aucun label global : vérifier namespace demo-app
    if kubectl get namespace demo-app >/dev/null 2>&1; then
        DEPLOYMENTS=("demo-app/demo-app-web")
    fi
fi

for dep in "${DEPLOYMENTS[@]}"; do
    NS="${dep%%/*}"
    NAME="${dep##*/}"
    log_info "Attente du déploiement : ${BOLD}${NAME}${NC} (namespace: ${CYAN}${NS}${NC})..."
    kubectl rollout status "deployment/${NAME}" -n "${NS}" --timeout=180s || {
        log_warn "Le déploiement ${NAME} n'a pas atteint le statut Ready dans les délais impartis."
    }
done

# 6. Récapitulatif des ressources déployées
echo -e "\n${CYAN}${BOLD}=== Récapitulatif des Pods Applicatifs ===${NC}\n"
kubectl get pods -A -l 'app.kubernetes.io/part-of=demo-app-suite' -o wide 2>/dev/null || kubectl get pods -n demo-app -o wide

echo -e "\n${CYAN}${BOLD}=== Récapitulatif des Services Applicatifs ===${NC}\n"
kubectl get svc -n demo-app -o wide

echo -e "\n${CYAN}${BOLD}=== Récapitulatif des Volumes Persistants (PVC) ===${NC}\n"
kubectl get pvc -n demo-app -o wide

log_success "Déploiement applicatif terminé avec succès !"
