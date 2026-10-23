# ==============================================================================
# GÉNÉRATION AUTOMATIQUE DE L'INVENTAIRE ANSIBLE
# ==============================================================================

resource "local_file" "ansible_inventory" {
  content = <<-EOT
# ==============================================================================
# Inventaire Ansible généré automatiquement par Terraform
# Ne pas modifier manuellement.
# ==============================================================================

[k3s_master]
%{if contains(keys(oci_core_instance.nodes), "k3s-master")}
k3s-master ansible_host=${oci_core_instance.nodes["k3s-master"].public_ip} private_ip=${oci_core_instance.nodes["k3s-master"].private_ip} ansible_user=ubuntu
%{endif}

[k3s_workers]
%{for k, v in oci_core_instance.nodes~}
%{if k != "k3s-master"~}
${k} ansible_host=${v.public_ip} private_ip=${v.private_ip} ansible_user=ubuntu
%{endif~}
%{endfor~}

[k3s_cluster:children]
k3s_master
k3s_workers

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30'
EOT

  filename             = "${path.module}/../ansible/inventory.ini"
  file_permission      = "0644"
  directory_permission = "0755"
}
