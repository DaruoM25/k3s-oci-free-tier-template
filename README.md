# K3s Multi-Node Cluster on OCI Always Free (Ampere A1) - Template

Ce dépôt constitue un **template d'infrastructure-as-code (IaC) et GitOps** prêt à l'emploi pour déployer un cluster Kubernetes **K3s hautement disponible de 4 nœuds** sur l'offre **Always Free** d'Oracle Cloud Infrastructure (OCI).

---

## 1. Architecture Always Free

L'offre Always Free d'Oracle Cloud alloue gratuitement et à vie jusqu'à **4 OCPUs ARM64 Ampere A1, 24 Go de RAM et 200 Go de volume de boot**. Ce template exploite 100 % de ce quota :

| Nœud | Rôle | Shape | OCPU | RAM | Disque Boot | Système |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `k3s-master` | Control Plane K3s & Caddy Ingress | `VM.Standard.A1.Flex` | 1 | 6 Go | 50 Go | Ubuntu 24.04 ARM |
| `k3s-worker-1` | Worker applicatif | `VM.Standard.A1.Flex` | 1 | 6 Go | 50 Go | Ubuntu 24.04 ARM |
| `k3s-worker-2` | Worker applicatif | `VM.Standard.A1.Flex` | 1 | 6 Go | 50 Go | Ubuntu 24.04 ARM |
| `k3s-worker-3` | Worker applicatif | `VM.Standard.A1.Flex` | 1 | 6 Go | 50 Go | Ubuntu 24.04 ARM |
| **Total** | **4 VMs (1 Master + 3 Workers)** | | **4** | **24 Go** | **200 Go** | *100 % Gratuit* |

### Composants clés
- **K3s (v1.30+)** : Distribution Kubernetes légère certifiée CNCF, avec Traefik désactivé au profit d'un Ingress reverse-proxy Caddy natif sur l'hôte.
- **Flannel CNI** : Réseau overlay VXLAN inter-nœuds avec règles de sécurité VCN optimisées.
- **Caddy Ingress** : Reverse-proxy haute performance gérant l'émission et le renouvellement automatique des certificats SSL/TLS Let's Encrypt.
- **Monitoring** : Prometheus Node Exporter préinstallé sur le port 9100 sur chaque instance.

---

## 2. Prérequis

Avant de déployer, assurez-vous d'avoir installé sur votre poste :
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (>= 1.8.0)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (>= 2.15)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Une paire de clés SSH (`~/.ssh/id_rsa` et `~/.ssh/id_rsa.pub`)
- Un compte **Oracle Cloud Infrastructure (OCI)** avec une clé d'API configurée

---

## 3. Guide de Déploiement

### Étape 1 : Provisionnement de l'infrastructure avec Terraform

1. Rendez-vous dans le sous-dossier `terraform/` :
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Renseignez vos identifiants OCI dans `terraform.tfvars` :
   ```hcl
   tenancy_ocid        = "ocid1.tenancy.oc1..votre_tenancy_ocid"
   compartment_ocid    = "ocid1.compartment.oc1..votre_compartment_ocid"
   region              = "eu-frankfurt-1"
   user_ocid           = "ocid1.user.oc1..votre_user_ocid"
   fingerprint         = "xx:xx:xx:..."
   private_key_path    = "~/.oci/oci_api_key.pem"
   ssh_public_key_path = "~/.ssh/id_rsa.pub"
   ```

3. Initialisez Terraform et appliquez le provisionnement :
   ```bash
   terraform init
   # Option A : Apply standard
   terraform apply
   # Option B : Utiliser le script de sonde multi-AD anti-OutOfCapacity
   ../scripts/provision_nodes.sh
   ```
   *Terraform génère automatiquement le fichier d'inventaire `ansible/inventory.ini` avec les adresses IP publiques et privées des instances.*

---

### Étape 2 : Configuration du cluster avec Ansible

1. Déplacez-vous dans le sous-dossier `ansible/` :
   ```bash
   cd ../ansible
   ```

2. Personnalisez votre nom de domaine et contact SSL dans `group_vars/all.yml` :
   ```yaml
   caddy_admin_email: "votre-email@example.com"
   caddy_vhosts:
     - name: "demo-app"
       domains:
         - "your-app.duckdns.org"
       upstream: "127.0.0.1:30080"
       enable_healthz: true
   ```

3. Lancez le playbook orchestrateur :
   ```bash
   ansible-playbook -i inventory.ini site.yml
   ```
   *Ce playbook configure les nœuds, installe K3s Master et Workers, configure les règles iptables, déploie Caddy et rapatrie localement le fichier `k3s-kubeconfig.yaml`.*

---

### Étape 3 : Déploiement des applications Kubernetes

1. Exportez le kubeconfig généré :
   ```bash
   export KUBECONFIG=$(pwd)/ansible/k3s-kubeconfig.yaml
   kubectl get nodes -o wide
   ```

2. Appliquez les manifestes applicatifs (exemple `demo-app` Web + PostgreSQL) :
   ```bash
   chmod +x ./scripts/deploy_k8s_apps.sh
   ./scripts/deploy_k8s_apps.sh
   ```

3. Vérifiez les pods et services actifs :
   ```bash
   kubectl get pods -n demo-app
   kubectl get svc -n demo-app
   ```

---

## 4. Configuration SSL Automatique (Caddy & DuckDNS)

1. Créez un sous-domaine gratuit sur [DuckDNS](https://www.duckdns.org/) pointant vers l'adresse IP publique du nœud Master (`k3s-master`).
2. Indiquez ce domaine dans `ansible/group_vars/all.yml`.
3. Dès que le playbook Ansible s'exécute, Caddy intercepte le port 80/443 sur l'hôte et déclenche le challenge ACME HTTP-01 ou TLS-ALPN pour obtenir un certificat SSL valide.
4. Votre application est immédiatement accessible de manière sécurisée sur `https://your-app.duckdns.org`.

---

## 5. Automatisation CI/CD (GitHub Actions)

Ce template inclut deux workflows GitHub Actions dans `.github/workflows/` :
- `deploy.yml` : Automatise le provisionnement Terraform et le déploiement Ansible périodiquement via un cron pour chasser les capacités Ampere A1 libérées par Oracle Cloud.
- `security-scan.yml` : Scanner de secrets automatisé basé sur Gitleaks avec allowlist [.gitleaks.toml](.gitleaks.toml) pour protéger le dépôt contre les fuites d'identifiants.

### Secrets GitHub requis (si utilisation de GitHub Actions) :
| Secret GitHub | Description |
| :--- | :--- |
| `OCI_TENANCY_OCID` | OCID de votre Tenancy Oracle Cloud |
| `OCI_USER_OCID` | OCID de l'utilisateur API OCI |
| `OCI_FINGERPRINT` | Empreinte de la clé d'API OCI |
| `OCI_KEY_CONTENT` | Contenu texte complet de la clé privée PEM OCI |
| `OCI_REGION` | Région OCI (ex: `eu-frankfurt-1`) |
| `SSH_PRIVATE_KEY` | Clé privée SSH pour administrer les VMs |
| `SSH_PUBLIC_KEY` | Clé publique SSH injectée dans les nœuds |
| `OCI_S3_ACCESS_KEY_ID` | Clé d'accès client S3 pour le backend Terraform Object Storage |
| `OCI_S3_SECRET_ACCESS_KEY` | Clé secrète client S3 correspondante |
| `OCI_NAMESPACE` | Namespace Object Storage de votre tenancy |

---

## 6. Structure du Projet

```plaintext
.
├── .github/workflows/
│   ├── deploy.yml              # Pipeline CI/CD provisionnement + configuration
│   └── security-scan.yml       # Scanner de secrets Gitleaks
├── .gitignore                  # Exclusion stricte des clés, kubeconfigs et tfstates
├── .gitleaks.toml              # Allowlist Gitleaks pour templates et placeholders
├── ansible/
│   ├── ansible.cfg             # Optimisations SSH et pipelining
│   ├── site.yml                # Playbook orchestrateur principal
│   ├── group_vars/all.yml      # Variables globales (K3s, Caddy, Ingress)
│   └── roles/
│       ├── common/             # Prise en main OS, sysctl, iptables OCI
│       ├── k3s_master/         # Installation K3s Server, extraction token
│       ├── k3s_worker/         # Jonction automatique des 3 workers
│       ├── caddy_ingress/      # Ingress Caddy natif (ports 80/443 SSL)
│       └── monitoring/         # Node Exporter systemd (port 9100)
├── k8s/
│   ├── apps/demo-app/          # Manifestes applicatifs de démonstration (Web + DB)
│   └── templates/              # Modèle de service NodePort / Ingress
├── scripts/
│   ├── provision_nodes.sh      # Sonde multi-AD et apply conditionnel anti-OutOfCapacity
│   └── deploy_k8s_apps.sh      # Script de déploiement et validation kubectl
└── terraform/
    ├── versions.tf             # Providers et backend S3 OCI
    ├── variables.tf            # Définitions des variables
    ├── terraform.tfvars.example# Exemple de variables locales
    ├── network.tf              # VCN, Subnet public, Route Tables, Security Lists
    ├── compute.tf              # 4 instances Ampere A1 (1 Master + 3 Workers)
    ├── outputs.tf              # Export des IPs publiques et privées
    └── inventory.tf            # Générateur d'inventaire Ansible dynamique
```

---

## 7. Licence

Ce projet est distribué sous licence MIT. Vous êtes libre de l'utiliser, le modifier et le distribuer pour vos propres infrastructures.
