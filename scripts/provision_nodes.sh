#!/usr/bin/env bash
# ==============================================================================
# Script de provisionnement résilient pour K3s sur OCI Always Free (Ampere A1)
# 
# Objectifs :
# 1. Phase 1 : Provisionne et verrouille l'infrastructure réseau (VCN/Subnet/SL).
# 2. Phase 2 : Sonde la disponibilité A1 sur les 3 ADs de Francfort (AD-1, AD-2, AD-3)
#    et applique terraform de manière ciblée (-target) UNIQUEMENT lorsqu'un AD a du stock.
# 3. Évite la saturation du state Terraform et les boucles aveugles.
# ==============================================================================

set -euo pipefail

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Répertoire du projet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Configuration
NODES=("k3s-master" "k3s-worker-1" "k3s-worker-2" "k3s-worker-3")
MAX_RETRIES=${MAX_RETRIES:-60} # 60 itérations par défaut (~30-45 min max par run)
RETRY_DELAY=${RETRY_DELAY:-30}  # 30 secondes d'attente entre deux passes globales

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

log_step() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

# ------------------------------------------------------------------------------
# 1. Vérification des prérequis
# ------------------------------------------------------------------------------
log_step "Vérification des outils prérequis"

command -v terraform >/dev/null 2>&1 || { log_error "Terraform n'est pas installé ou absent du PATH."; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq n'est pas installé ou absent du PATH."; exit 1; }

cd "${TERRAFORM_DIR}"

# ------------------------------------------------------------------------------
# 2. Récupération dynamique des Availability Domains
# ------------------------------------------------------------------------------
log_step "Détection des Availability Domains de la région"

if command -v oci >/dev/null 2>&1; then
    log_info "Interrogation des ADs via OCI CLI..."
    # Récupération des noms complets des ADs
    ADS=($(oci iam availability-domain list --query "data[].name" --raw-output 2>/dev/null || true))
fi

# Fallback si OCI CLI n'est pas encore configuré ou échoue
if [ -z "${ADS:-}" ] || [ ${#ADS[@]} -eq 0 ]; then
    log_warn "OCI CLI non configuré ou échec. Extraction des ADs depuis Terraform..."
    ADS=($(terraform console <<< 'data.oci_identity_availability_domains.ads.availability_domains[*].name' 2>/dev/null | tr -d '[],"' || true))
fi

# Dernier recours : format standard OCI Francfort
if [ -z "${ADS:-}" ] || [ ${#ADS[@]} -eq 0 ]; then
    log_warn "Utilisation des valeurs par défaut pour eu-frankfurt-1..."
    # Les noms d'AD sur OCI incluent souvent le préfixe de la tenancy, ex: "RoNo:EU-FRANKFURT-1-AD-1"
    # On initialise Terraform pour interroger data.oci_identity_availability_domains.ads
    terraform refresh >/dev/null 2>&1 || true
    ADS=($(terraform output -json cluster_nodes_summary 2>/dev/null | jq -r 'keys[]' 2>/dev/null || true))
fi

log_info "Availability Domains identifiés : ${ADS[*]:-Inconnu}"

# ------------------------------------------------------------------------------
# 3. Phase 1 : Déploiement et verrouillage du réseau de base
# ------------------------------------------------------------------------------
log_step "Phase 1 : Provisionnement et verrouillage de l'infrastructure réseau"

NETWORK_TARGETS=(
    "oci_core_vcn.k3s_vcn"
    "oci_core_internet_gateway.k3s_igw"
    "oci_core_route_table.k3s_rt"
    "oci_core_security_list.k3s_sl"
    "oci_core_subnet.k3s_subnet"
)

TARGET_ARGS=""
for target in "${NETWORK_TARGETS[@]}"; do
    TARGET_ARGS="${TARGET_ARGS} -target=${target}"
done

log_info "Application Terraform ciblée sur le réseau..."
if terraform apply -auto-approve ${TARGET_ARGS}; then
    log_success "Phase 1 terminée : Réseau, passerelle, tables de routage et Security List verrouillés."
else
    log_error "Échec du provisionnement du réseau en Phase 1. Arrêt."
    exit 1
fi

# ------------------------------------------------------------------------------
# 4. Phase 2 : Sonde de disponibilité et apply conditionnel ciblé
# ------------------------------------------------------------------------------
log_step "Phase 2 : Sonde de capacité A1 et provisionnement ciblé des 4 VMs"

# Fonction pour tester si un nœud existe et est RUNNING dans le state
is_node_provisioned() {
    local node_name="$1"
    local state_list
    state_list=$(terraform state list 2>/dev/null || true)
    if echo "${state_list}" | grep -Fq "oci_core_instance.nodes[\"${node_name}\"]"; then
        return 0 # Existe
    else
        return 1 # N'existe pas
    fi
}

# Fonction pour obtenir la liste des nœuds restants à créer
get_missing_nodes() {
    local missing=()
    for node in "${NODES[@]}"; do
        if ! is_node_provisioned "${node}"; then
            missing+=("${node}")
        fi
    done
    echo "${missing[@]}"
}

# Boucle de provisionnement résiliente
ATTEMPT=1
while [ ${ATTEMPT} -le ${MAX_RETRIES} ]; do
    MISSING_NODES=($(get_missing_nodes))
    TOTAL_MISSING=${#MISSING_NODES[@]}

    if [ ${TOTAL_MISSING} -eq 0 ]; then
        log_success "Toutes les 4 VMs K3s sont déjà provisionnées et enregistrées dans l'état Terraform !"
        break
    fi

    log_info "Passe ${ATTEMPT}/${MAX_RETRIES} : ${TOTAL_MISSING} nœuds restants à provisionner : [${MISSING_NODES[*]}]"

    for node in "${MISSING_NODES[@]}"; do
        log_info "Traitement du nœud : ${BOLD}${node}${NC}"
        NODE_PROVISIONED=false

        # Si nous avons pu détecter la liste des ADs, on teste chaque AD
        # Sinon on tente l'apply sans forcer l'AD (laisse terraform utiliser l'ad par défaut)
        AD_LIST=("${ADS[@]:-default}")

        for ad in "${AD_LIST[@]}"; do
            log_info "-> Sonde de capacité A1 pour '${node}' sur l'AD : ${CYAN}${ad}${NC}..."
            
            VAR_ARG=""
            if [ "${ad}" != "default" ]; then
                VAR_ARG="-var=\"node_availability_domains={\\\"${node}\\\":\\\"${ad}\\\"}\""
            fi

            # Exécution ciblée sous surveillance
            APPLY_LOG=$(mktemp)
            set +e
            # shellcheck disable=SC2086
            eval terraform apply -auto-approve -target="oci_core_instance.nodes[\\\"${node}\\\"]" ${VAR_ARG} > "${APPLY_LOG}" 2>&1
            EXIT_CODE=$?
            set -e

            if [ ${EXIT_CODE} -eq 0 ]; then
                log_success "Capacité disponible ! Nœud '${node}' provisionné avec succès sur ${ad} et consigné dans le state !"
                NODE_PROVISIONED=true
                rm -f "${APPLY_LOG}"
                break
            else
                # Analyse de l'erreur
                if grep -Eqi "OutOfCapacity|Out of host capacity|LimitExceeded|500" "${APPLY_LOG}"; then
                    log_warn "Ressource indisponible (OutOfCapacity) sur ${ad} pour '${node}'. Test de l'AD suivant..."
                else
                    log_error "Erreur inattendue lors de la tentative sur ${ad} :"
                    cat "${APPLY_LOG}"
                fi
                rm -f "${APPLY_LOG}"
            fi
        done

        if [ "${NODE_PROVISIONED}" = "true" ]; then
            log_info "Progression enregistrée pour '${node}'."
        else
            log_warn "Aucune capacité A1 trouvée sur aucun AD pour '${node}' lors de cette passe."
        fi
    done

    # Vérification post-passe
    MISSING_NODES=($(get_missing_nodes))
    if [ ${#MISSING_NODES[@]} -eq 0 ]; then
        log_success "Félicitations ! Les 4 nœuds ont tous été provisionnés avec succès !"
        break
    fi

    log_info "Temporisation de ${RETRY_DELAY}s avant la prochaine passe de détection (évite le rate-limiting)..."
    sleep "${RETRY_DELAY}"
    ATTEMPT=$((ATTEMPT + 1))
done

# ------------------------------------------------------------------------------
# 5. Finalisation et génération de l'inventaire Ansible
# ------------------------------------------------------------------------------
log_step "Finalisation et synchronisation de l'inventaire Ansible"

log_info "Exécution d'un apply global de synchronisation..."
terraform apply -auto-approve

INVENTORY_FILE="${PROJECT_ROOT}/ansible/inventory.ini"
if [ -f "${INVENTORY_FILE}" ]; then
    log_success "Fichier d'inventaire généré avec succès : ${INVENTORY_FILE}"
    echo -e "\n${BOLD}--- Contenu de l'inventaire Ansible ---${NC}"
    cat "${INVENTORY_FILE}"
    echo -e "${BOLD}----------------------------------------${NC}\n"
else
    log_warn "Le fichier d'inventaire n'a pas encore été généré (nœuds peut-être incomplets)."
fi

# Affichage du récapitulatif
log_step "Récapitulatif de l'infrastructure K3s"
terraform output -json cluster_nodes_summary | jq . || terraform output

MISSING_AFTER=($(get_missing_nodes))
if [ ${#MISSING_AFTER[@]} -gt 0 ]; then
    log_warn "Attention : Il reste ${#MISSING_AFTER[@]} nœuds non alloués : [${MISSING_AFTER[*]}]"
    log_warn "Relancez ce script ou laissez le cron GitHub Actions continuer la détection de capacité."
    exit 2
else
    log_success "Cluster complet et prêt pour le déploiement Ansible !"
    exit 0
fi
