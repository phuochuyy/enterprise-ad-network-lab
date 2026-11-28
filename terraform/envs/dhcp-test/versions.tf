terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.124"
    }
  }

  # Throwaway state: this env exists only for the duration of a smoke test.
  backend "local" {}
}
