 terraform {
  backend "remote" {
    organization = "hogwarts"

    workspaces {
      name = "prod-eu-central"
    }
  }

  required_providers {
    linode = {
      source = "linode/linode"
      version = "~> 1.27"
    }

    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 3.12"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

provider "cloudflare" { 
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

resource "linode_instance" "server1" {
  label = var.server1_label
  tags = [ "prod", "server" ]
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
      "dnf -q -y install dnf-automatic cockpit-pcp docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-scan-plugin wireguard-tools bind restic tailscale git tmux",
      "pip3 install linode-cli",
      "systemctl daemon-reload",
      "systemctl enable --now docker",
      "systemctl enable --now tailscaled",

      # restore backups
      "export RESTIC_REPOSITORY='${var.server1_restic_repository}'",
      "export RESTIC_PASSWORD='${var.server1_restic_password}'",
      "export AWS_ACCESS_KEY_ID='${var.server1_restic_aws_access_key_id}'",
      "export AWS_SECRET_ACCESS_KEY='${var.server1_aws_secret_access_key}'",
      "restic restore ${var.server1_snapshot} --target ${var.server1_snapshot_target}",

      # misc config
      "hostnamectl set-hostname ${var.server1_hostname}",
      "timedatectl set-timezone Europe/Berlin",
      "sed -i 's/PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config",

      # Add Tailscale login
      "tailscale up --authkey=${var.server1_tskey}",

      # .bashrc
      "echo -e '## Aliases\nalias ls='ls -ahlG'\ncdls() { cd '$@' && ls; }\nalias cd='cdls'\n\n# Restart linode1, simply running reboot from the OS doesn't bring up the Linode\nexport LINODE_TOKEN=${var.linode_selfrestart_token}\nalias reboot='linode-cli linodes reboot ${linode_instance.server1.id}'\n' >> .bashrc",

      # firewall config
      "firewall-cmd --permanent --service=http --add-port=80/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=http",

      "firewall-cmd --permanent --service=https --add-port=443/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=https",

      "firewall-cmd --permanent --new-service=etlegacy",
      "firewall-cmd --permanent --service=etlegacy --add-port=27960/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=etlegacy",

      "firewall-cmd --permanent --new-service=minecraft",
      "firewall-cmd --permanent --service=minecraft --add-port=19132-19133/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=minecraft",

      "firewall-cmd --reload",

      "sed -i 's/TARGET_DOMAIN=.*/TARGET_DOMAIN=${var.server1_hostname}/' /compose/traefik-cloudflare-companion/compose.yaml",
      "for d in /compose/*/ ; do (cd $d && docker compose up -d); done",

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