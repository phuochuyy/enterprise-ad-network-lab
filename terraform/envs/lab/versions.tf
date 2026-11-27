terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.124"
    }
  }

  # Single operator lab: local state, gitignored. Back it up with `scripts/tf.sh state pull`.
  backend "local" {}
}
