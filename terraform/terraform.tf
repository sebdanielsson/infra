terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

provider "cloudflare" {
  api_key = var.cloudflare_api_key
  email   = var.cloudflare_email
}

variable "cloudflare_api_key" {
  description = "API key for Cloudflare"
  type        = string
  sensitive   = true
}

variable "cloudflare_email" {
  description = "Email associated with Cloudflare account"
  type        = string
}
