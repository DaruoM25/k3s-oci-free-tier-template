# ==============================================================================
# PHASE 1 : INFRASTRUCTURE RÉSEAU ET SÉCURITÉ
# ==============================================================================

# VCN K3s (10.0.0.0/16)
resource "oci_core_vcn" "k3s_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "k3s-vcn"
  dns_label      = "k3svcn"

  freeform_tags = {
    "Project"     = "k3s-oci-alwaysfree"
    "Environment" = "Production"
  }
}

# Passerelle Internet (IGW)
resource "oci_core_internet_gateway" "k3s_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s_vcn.id
  display_name   = "k3s-internet-gateway"
  enabled        = true

  freeform_tags = {
    "Project" = "k3s-oci-alwaysfree"
  }
}

# Table de routage publique pointant vers l'IGW
resource "oci_core_route_table" "k3s_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s_vcn.id
  display_name   = "k3s-public-routetable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.k3s_igw.id
    description       = "Default gateway to Internet"
  }

  freeform_tags = {
    "Project" = "k3s-oci-alwaysfree"
  }
}

# Security List (Contrôle des flux d'entrée / sortie)
resource "oci_core_security_list" "k3s_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s_vcn.id
  display_name   = "k3s-security-list"

  # --- RÈGLES EGRESS (SORTIE LIBRE) ---
  egress_security_rules {
    destination      = "0.0.0.0/0"
    protocol         = "all"
    destination_type = "CIDR_BLOCK"
    description      = "Allow all outbound traffic"
  }

  # --- RÈGLES INGRESS (ENTRÉE) ---

  # 1. SSH (Port 22)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "SSH administrative access"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # 2. HTTP (Port 80 pour Caddy Ingress)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTP Ingress traffic (Caddy)"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # 3. HTTPS (Port 443 pour Caddy Ingress)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTPS Ingress traffic (Caddy)"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # 4. K3s Kubernetes API Server (Port 6443)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "Kubernetes API Server access"

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # 5. Prometheus Node Exporter (Port 9100)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "Prometheus Node Exporter metrics scraping"

    tcp_options {
      min = 9100
      max = 9100
    }
  }

  # 6. Trafic Inter-VCN complet (Flannel VXLAN UDP 8472, Kubelet 10250, Pods, Services)
  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr
    description = "Allow all inter-cluster internal traffic (VXLAN 8472, Kubelet 10250, Pods)"
  }

  # 7. ICMP Path MTU Discovery
  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    description = "Path MTU discovery"

    icmp_options {
      type = 3
      code = 4
    }
  }

  freeform_tags = {
    "Project" = "k3s-oci-alwaysfree"
  }
}

# Sous-réseau public hébergeant les 4 instances K3s
resource "oci_core_subnet" "k3s_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.k3s_vcn.id
  cidr_block                 = var.subnet_cidr
  display_name               = "k3s-public-subnet"
  dns_label                  = "k3ssubnet"
  route_table_id             = oci_core_route_table.k3s_rt.id
  security_list_ids          = [oci_core_security_list.k3s_sl.id]
  prohibit_public_ip_on_vnic = false

  freeform_tags = {
    "Project" = "k3s-oci-alwaysfree"
  }
}
