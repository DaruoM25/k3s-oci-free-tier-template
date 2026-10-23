terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.40.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
  }

  # Backend S3 compatible avec OCI Object Storage
  # Fournir les credentials et endpoint via terraform init -backend-config=...
  # ou via le fichier terraform/backend.hcl
  backend "s3" {
    bucket                      = "terraform-states"
    key                         = "k3s-oci-cluster/terraform.tfstate"
    region                      = "eu-frankfurt-1"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path != "" ? var.private_key_path : null
  private_key      = var.private_key != "" ? var.private_key : null
  region           = var.region
}
