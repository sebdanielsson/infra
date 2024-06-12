terraform {
  cloud {
    organization = "hogwarts"

    workspaces {
      name = "prod-eu-central"
    }
  }

  required_providers {
    linode = {
      source = "linode/linode"
      version = "2.22.0"
    }

    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "4.35.0"
    }
  }
}

resource "linode_firewall" "web" {
  label = "web"
  tags  = ["web"]

  inbound {
    label    = "http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "http3"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "minecraft"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "19132-19133"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "etlegacy"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "27960"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound_policy = "DROP"

  outbound_policy = "ACCEPT"

  linodes = [linode_instance.server1.id]
}

provider "linode" {
  token = var.linode_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "linode_instance" "server1" {
  label = var.server1_label
  tags = [ "prod" ]
  image = var.server1_image
  region = var.server1_region
  type = var.server1_type
  authorized_keys = [ var.server1_authorized_keys ]
  root_pass = var.server1_root_pass
  backups_enabled = var.server1_backups
  watchdog_enabled = var.server1_watchdog
  swap_size = var.server1_swap

  provisioner "remote-exec" {
    inline = [
      # upgrade system
      "dnf -q -y upgrade",
      
      # install software
      "dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo",
      "dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo",
      "dnf config-manager --add-repo https://pkg.cloudflare.com/cloudflared-ascii.repo",
      "dnf -q -y install dnf-automatic cockpit-pcp docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-scan-plugin wireguard-tools bind git restic tailscale tmux python3-pip cloudflared",
      "DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=${var.datadog_api_key} DD_SITE='datadoghq.com' bash -c '$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)'",
      "wget -qO - https://raw.githubusercontent.com/CupCakeArmy/autorestic/master/install.sh | bash",
      "pip3 install linode-cli",
      "systemctl daemon-reload",
      "systemctl enable --now docker",
      
      # misc config
      "hostnamectl set-hostname ${var.server1_hostname}",
      "timedatectl set-timezone Europe/Berlin",
      "sed -i 's/PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config",
      
      # Configure Datadog and start service
      "printf '\n# Added by Sebastian through Terraform on creation\nlogs_enabled: true\n' >> /etc/datadog-agent/datadog.yaml",
      "printf \"instances:\n  - file_system_exclude:\n    - tmpfs\n    - none\n    - shm\n    - nsfs\n    - netns\n    - overlay\n    - tracefs\n\" >> /etc/datadog-agent/conf.d/disk.d/disk.yml",
      "systemctl enable --now datadog-agent",
      
      # Start Tailscale and login
      "systemctl enable --now tailscaled",
      "tailscale up --authkey=${var.server1_tskey} --ssh",
      
      # .bashrc
      "printf \"\n## Aliases\nalias ls='ls -ahl --color=auto'\n\n# Restart linode1, simply running reboot from the OS doesn't bring up the Linode\nexport LINODE_CLI_TOKEN=${var.linode_selfrestart_token}\nalias reboot='linode-cli linodes reboot ${linode_instance.server1.id}'\n\" >> .bashrc",
      
      # firewall config
      "firewall-cmd --permanent --add-interface=tailscale0 --zone=internal",
      "firewall-cmd --zone=internal --permanent --add-service=cockpit",
      
      "firewall-cmd --zone=FedoraServer --permanent --add-service=http",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=https",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=http3",

      "firewall-cmd --reload",
      
      # Following two rows requires the restoration of docker-compose fieles first
      #"sed -i 's/TARGET_DOMAIN=.*/TARGET_DOMAIN=${var.server1_hostname}/' /docker/compose/enabled/traefik-cloudflare-companion/compose.yaml",
      #"for d in /docker/compose/enabled/*/ ; do (cd $d && docker compose up -d); done",
      
      # complete
      "echo 'Please restart the server from the dashboard for all changes to take effect.'",
    ]

    connection {
      type = "ssh"
      user = "root"
      password = var.server1_root_pass
      host = linode_instance.server1.ip_address
    }
  }   
}

resource "cloudflare_record" "dns_ipv4_server1" {
  depends_on = [linode_instance.server1]
  zone_id = var.cloudflare_zone_id
  name    = var.server1_label
  value   = linode_instance.server1.ip_address
  type    = "A"
  ttl     = 1

  timeouts {
    create = "2m"
    update = "2m"
  }
}

resource "cloudflare_record" "dns_ipv6_server1" {
  depends_on = [linode_instance.server1]
  zone_id = var.cloudflare_zone_id
  name    = var.server1_label
  value   = trimsuffix(linode_instance.server1.ipv6, "/128")
  type    = "AAAA"
  ttl     = 1

  timeouts {
    create = "2m"
    update = "2m"
  }
}

### Variables ###

# Linode tokens
variable "linode_token" {
  
}

variable "linode_selfrestart_token" {
  
}

# Cloudflare
variable "cloudflare_api_token" {
  
}

variable "cloudflare_zone_id" {
  
}

# Linode instance
variable "server1_label" {
  description = "Label for server1"
  type = string
}

variable "server1_hostname" {
  description = "Hostname for server1"
  type = string
}

variable "server1_root_pass" {
  description = "Password for the root user"
  type = string
}

variable "server1_authorized_keys" {
  description = "authorized_keys for server1"
  type = string
}

variable "server1_image" {
  description = "OS image for server1"
  type = string
}

variable "server1_region" {
  description = "Region for server1"
  type = string
}

variable "server1_type" {
  description = "Instance type for server1"
  type = string
}

variable "server1_swap" {
  description = "Swap size for server1"
  type = number
}

variable "server1_backups" {
  description = "Linode backups for server1"
  type = bool
}

variable "server1_watchdog" {
  description = "Watchdog for server1"
  type = bool
}

# Tailscale authkey
variable "server1_tskey" {
  description = "Tailscale authkey"
  type = string
}

# Datadog API key
variable "datadog_api_key" {
  description = "Datadog API Key"
  type = string
}

# Restic restore
variable "server1_restic_repository" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
}

variable "server1_restic_password" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
}

variable "server1_restic_aws_access_key_id" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
}

variable "server1_aws_secret_access_key" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
}

variable "server1_snapshot" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
}

variable "server1_snapshot_target" {
  description = "Where to put restored files from snapshot1"
  type = string
}
