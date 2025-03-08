variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Region for GCP resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for GCP resources"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "GCE instance machine type"
  type        = string
  default     = "e2-micro"
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  network_interface = "ens4"
  wireguard_port    = 51820
  vpn_network       = "10.8.0"
  vpn_netmask       = "24"
  server_ip         = "${local.vpn_network}.1"
  client_ip         = "${local.vpn_network}.2"
}

resource "google_compute_instance" "wireguard" {
  name         = "wireguard-vpn"
  machine_type = var.machine_type
  zone         = var.zone
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size
    }
  }
  
  network_interface {
    network = "default"
    access_config {}
  }
  
  metadata = {
    enable-oslogin = "TRUE"
  }
  
  tags = ["wireguard-vpn", "allow-ssh"]
  
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e

    # Install WireGuard
    apt-get update && apt-get install -y wireguard

    # Generate server and client keys
    umask 077
    wg genkey | tee /etc/wireguard/server_private.key
    cat /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    wg genkey | tee /etc/wireguard/client_private.key
    cat /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key

    # Create server config
    cat > /etc/wireguard/wg0.conf <<-CONFIG
    [Interface]
    PrivateKey = $(cat /etc/wireguard/server_private.key)
    Address = ${local.server_ip}/${local.vpn_netmask}
    ListenPort = ${local.wireguard_port}
    PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${local.network_interface} -j MASQUERADE
    PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${local.network_interface} -j MASQUERADE

    [Peer]
    PublicKey = $(cat /etc/wireguard/client_public.key)
    AllowedIPs = ${local.client_ip}/32
    CONFIG

    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf

    # Create client config
    SERVER_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")
    
    cat > /etc/wireguard/client.conf <<-CONFIG
    [Interface]
    PrivateKey = $(cat /etc/wireguard/client_private.key)
    Address = ${local.client_ip}/${local.vpn_netmask}
    DNS = 8.8.8.8

    [Peer]
    PublicKey = $(cat /etc/wireguard/server_public.key)
    Endpoint = $SERVER_IP:${local.wireguard_port}
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    CONFIG

    # Start WireGuard
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
  EOF
  
  service_account {
    scopes = ["compute-ro"]
  }
}

resource "google_compute_firewall" "wireguard" {
  name    = "allow-wireguard"
  network = "default"
  
  allow {
    protocol = "udp"
    ports    = ["${local.wireguard_port}"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["wireguard-vpn"]
}

resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh"
  network = "default"
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-ssh"]
}

resource "google_compute_project_metadata_item" "oslogin" {
  key   = "enable-oslogin"
  value = "TRUE"
}

output "instance_ip" {
  value = google_compute_instance.wireguard.network_interface[0].access_config[0].nat_ip
}

output "client_config_instructions" {
  value = <<EOF
To retrieve the client configuration:
1. Connect to the instance: gcloud compute ssh wireguard-vpn --zone=${var.zone}
2. Get the client config: sudo cat /etc/wireguard/client.conf
3. Copy the output to your WireGuard client
EOF
}