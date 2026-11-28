# Proxmox connection comes from the environment (scripts/packer.sh):
# PROXMOX_URL, PROXMOX_USERNAME (token id), PROXMOX_TOKEN.

variable "proxmox_node" {
  description = "Proxmox node to build on."
  type        = string
  default     = "pve"
}

variable "template_vm_id" {
  description = "VMID of the resulting template."
  type        = number
  default     = 9005
}

variable "template_name" {
  description = "Template name."
  type        = string
  default     = "tpl-opnsense-26.7"
}

variable "iso_file" {
  description = "OPNsense DVD (live + installer) ISO volume id."
  type        = string
  default     = "local:iso/OPNsense-26.7-dvd-amd64.iso"
}

variable "storage_pool" {
  description = "Datastore for the system disk."
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "System disk (UFS, no swap). Clones can grow it."
  type        = string
  default     = "16G"
}

variable "memory_mb" {
  description = "RAM for the build: the live system runs from memory while it copies itself to disk."
  type        = number
  default     = 3072
}

# --- Network: net0 = LAN (site trunk, vtnet0), net1 = WAN (vmbr1, vtnet1) ------
variable "lan_bridge" {
  description = "Bridge for the LAN NIC during the build (unused; clones attach their site trunk)."
  type        = string
  default     = "vmbr10"
}

variable "build_bridge" {
  description = "Simulated WAN with Internet through the host NAT (no DHCP)."
  type        = string
  default     = "vmbr1"
}

variable "build_ip" {
  description = "Static WAN address of the installed system during the build only."
  type        = string
  default     = "10.10.10.250"
}

variable "build_prefix" {
  description = "Prefix length of the build network."
  type        = number
  default     = 24
}

variable "build_gateway" {
  description = "Gateway of the build network (the Proxmox host NAT); also the only admin host."
  type        = string
  default     = "10.10.10.1"
}

variable "build_dns" {
  description = "DNS server used during the build."
  type        = string
  default     = "1.1.1.1"
}

# --- Secrets (scripts/packer.sh) -------------------------------------------------
variable "root_password_hash" {
  description = "crypt(3) SHA-512 hash of the OPNsense root password (PKR_VAR_root_password_hash)."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Lab automation public key authorised for root (PKR_VAR_ssh_public_key)."
  type        = string
}

variable "ssh_private_key_file" {
  description = "Private half of ssh_public_key, used by Packer's SSH communicator."
  type        = string
}
