variable "tenancy_ocid" {
  description = "OCID de la Tenancy OCI"
  type        = string
  default     = ""
}

variable "compartment_ocid" {
  description = "OCID du compartiment de déploiement (laisse vide pour utiliser la root tenancy)"
  type        = string
  default     = ""
}

variable "user_ocid" {
  description = "OCID de l'utilisateur OCI pour l'API"
  type        = string
  default     = ""
}

variable "fingerprint" {
  description = "Fingerprint de la clé d'API OCI"
  type        = string
  default     = ""
}

variable "private_key_path" {
  description = "Chemin vers la clé privée OCI API"
  type        = string
  default     = ""
}

variable "private_key" {
  description = "Contenu direct de la clé privée OCI API (prioritaire si non vide)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "region" {
  description = "Région OCI de déploiement"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "image_ocid" {
  description = "OCID de l'image Ubuntu 24.04 ARM"
  type        = string
  default     = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaatnudwzlqzctpx5rrxohiionypan5fngceqdbybtw6ve7oyhmnnqq"
}

variable "ssh_public_key" {
  description = "Contenu de la clé SSH publique injectée dans les VMs"
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Chemin local vers la clé SSH publique"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "vcn_cidr" {
  description = "Plage CIDR du VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Plage CIDR du sous-réseau public"
  type        = string
  default     = "10.0.1.0/24"
}

variable "node_availability_domains" {
  description = "Dictionnaire associant chaque nœud à son Availability Domain exact (injecté dynamiquement par provision_nodes.sh)"
  type        = map(string)
  default = {
    "k3s-master"   = ""
    "k3s-worker-1" = ""
    "k3s-worker-2" = ""
    "k3s-worker-3" = ""
  }
}

variable "node_ocpus" {
  description = "Nombre d'OCPU par VM (Total gratuit: 4 OCPUs max -> 1 par VM)"
  type        = number
  default     = 1
}

variable "node_memory_in_gbs" {
  description = "Quantité de RAM en Go par VM (Total gratuit: 24 Go max -> 6 Go par VM)"
  type        = number
  default     = 6
}

variable "boot_volume_size_in_gbs" {
  description = "Taille du boot volume en Go par VM (Total gratuit: 200 Go max -> 50 Go par VM)"
  type        = number
  default     = 50
}
