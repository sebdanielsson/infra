# Linode tokens
variable "linode_token" {
  description = "Linode API token"
  type = string
  sensitive = true
}

variable "linode_selfrestart_token" {
  description = "Linode self-restart token"
  type = string
  sensitive = true
}

# Cloudflare tokens
variable "cloudflare_email" {
  description = "Cloudflare account email"
  type = string
  sensitive = true
}

variable "cloudflare_api_key" {
  description = "Cloudflare API Key"
  type = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type = string
  sensitive = true
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
  sensitive = true
}

variable "server1_authorized_keys" {
  description = "authorized_keys for server1"
  type = string
  sensitive = true
}

variable "server1_image" {
  description = "OS image for server1"
  type = string
  default = "linode/fedora35"
}

variable "server1_region" {
  description = "Region for server1"
  type = string
  default = "eu-central"
}

variable "server1_type" {
  description = "Instance type for server1"
  type = string
  default = "g6-standard-1"
}

variable "server1_swap" {
  description = "Swap size for server1"
  default = 1024
}

variable "server1_backups" {
  description = "Linode backups for server1"
  type = bool
  default = false
}

variable "server1_watchdog" {
  description = "Watchdog for server1"
  type = bool
  default = false
}

# Tailscale authkey
variable "server1_tskey" {
  description = "Tailscale authkey"
  type = string
  sensitive = true
}

# Restic restore
variable "server1_restic_repository" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_restic_password" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_restic_aws_access_key_id" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_aws_secret_access_key" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_snapshot" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  default = "latest"
}

variable "server1_snapshot_target" {
  description = "Where to put restored files from snapshot1"
  type = string
  default = "/"
}
