# ==============================================================================
# PHASE 2 : INSTANCES COMPUTE AMPERE A1 (K3S MASTER & WORKERS)
# ==============================================================================

# Récupération des Availability Domains disponibles dans la région
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  # Définition des 4 nœuds et de leurs rôles
  cluster_nodes = {
    "k3s-master" = {
      role             = "master"
      default_ad_index = 0
    }
    "k3s-worker-1" = {
      role             = "worker"
      default_ad_index = 0
    }
    "k3s-worker-2" = {
      role             = "worker"
      default_ad_index = 1
    }
    "k3s-worker-3" = {
      role             = "worker"
      default_ad_index = 2
    }
  }

  # Clé SSH publique injectée
  ssh_key = var.ssh_public_key != "" ? var.ssh_public_key : (
    fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) : ""
  )
}

# 4 Instances Ampere A1 (1 Master + 3 Workers)
resource "oci_core_instance" "nodes" {
  for_each = local.cluster_nodes

  compartment_id = var.compartment_ocid
  display_name   = each.key

  # Détermine l'AD injecté par le script provision_nodes.sh ou prend l'AD par défaut
  availability_domain = lookup(var.node_availability_domains, each.key, "") != "" ? (
    var.node_availability_domains[each.key]
    ) : (
    data.oci_identity_availability_domains.ads.availability_domains[each.value.default_ad_index].name
  )

  # Profil matériel Always Free Ampere A1
  shape = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.k3s_subnet.id
    assign_public_ip = true
    display_name     = "${each.key}-vnic"
    hostname_label   = replace(each.key, "-", "")
  }

  metadata = {
    ssh_authorized_keys = local.ssh_key
    user_data = base64encode(<<-EOF
      #!/bin/bash
      echo "Initializing ${each.key}..."
    EOF
    )
  }

  freeform_tags = {
    "Project"  = "k3s-oci-alwaysfree"
    "Role"     = each.value.role
    "NodeName" = each.key
  }

  # CRUCIAL : ignore_changes sur availability_domain garantit qu'une fois
  # la VM créée dans l'AD ayant eu de la capacité, un terraform apply ultérieur
  # ne tentera JAMAIS de la détruire/recréer dans un autre AD.
  lifecycle {
    ignore_changes = [
      availability_domain,
      source_details[0].source_id
    ]
  }
}
