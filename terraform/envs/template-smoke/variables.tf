variable "pve_endpoint" {
  description = "Proxmox API endpoint."
  type        = string
  default     = "https://127.0.0.1:8006/"
}

variable "pve_insecure" {
  description = "Skip TLS verification (loopback to the host's self-signed cert)."
  type        = bool
  default     = true
}

variable "template_vm_id" {
  description = "Template under test (9001 ws2022-core, 9002 ws2022-desktop, 9003 win11)."
  type        = number
}

variable "os_type" {
  description = "Guest OS type of the template."
  type        = string
  default     = "win11"
}

variable "tpm" {
  description = "Attach TPM 2.0 (Windows 11 templates)."
  type        = bool
  default     = false
}

variable "disk_gb" {
  description = "Boot disk size; must be >= the template disk (WS2022 40, Win11 64)."
  type        = number
  default     = 40
}

variable "test_ip" {
  description = "Static IP the clone must come up with, on the build network vmbr1."
  type        = string
  default     = "10.10.10.60"
}

variable "bios" {
  description = "Firmware of the clone: ovmf (Windows templates) or seabios (Linux/OPNsense templates)."
  type        = string
  default     = "ovmf"
}

variable "memory_mb" {
  description = "RAM of the clone."
  type        = number
  default     = 4096
}

variable "ci_type" {
  description = "Cloud-init drive format: configdrive2 (cloudbase-init, Windows) or nocloud (Linux)."
  type        = string
  default     = "configdrive2"
}

variable "ci_username" {
  description = "Cloud-init user (Linux only; Windows templates keep their own Administrator)."
  type        = string
  default     = null
}

variable "ci_ssh_keys" {
  description = "SSH public keys for ci_username."
  type        = list(string)
  default     = []
}
