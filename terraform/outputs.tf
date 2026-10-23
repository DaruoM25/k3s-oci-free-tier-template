output "master_public_ip" {
  description = "Adresse IP publique du master K3s"
  value       = try(oci_core_instance.nodes["k3s-master"].public_ip, "")
}

output "master_private_ip" {
  description = "Adresse IP privée du master K3s"
  value       = try(oci_core_instance.nodes["k3s-master"].private_ip, "")
}

output "workers_public_ips" {
  description = "Adresses IP publiques des nœuds workers"
  value = {
    for k, v in oci_core_instance.nodes : k => v.public_ip if k != "k3s-master"
  }
}

output "workers_private_ips" {
  description = "Adresses IP privées des nœuds workers"
  value = {
    for k, v in oci_core_instance.nodes : k => v.private_ip if k != "k3s-master"
  }
}

output "cluster_nodes_summary" {
  description = "Résumé complet des nœuds du cluster"
  value = {
    for k, v in oci_core_instance.nodes : k => {
      id                  = v.id
      availability_domain = v.availability_domain
      public_ip           = v.public_ip
      private_ip          = v.private_ip
      state               = v.state
    }
  }
}
