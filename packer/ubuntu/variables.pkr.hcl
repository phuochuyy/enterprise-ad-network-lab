# Proxmox connection comes from the environment (scripts/packer.sh):
# PROXMOX_URL, PROXMOX_USERNAME (token id), PROXMOX_TOKEN.

variable "proxmox_node" {
  description = "Proxmox node to build on."
  type        = string
  default     = "pve"
}

variable "base_vm_id" {
  description = "Unmodified cloud-image template created by Terraform (terraform/envs/lab/base-images.tf)."
  type        = number
  default     = 9100
}

variable "template_vm_id" {
  description = "VMID of the resulting golden template."
  type        = number
  default     = 9004
}

variable "template_name" {
  description = "Template name."
  type        = string
  default     = "tpl-ubuntu-2404"
}

variable "build_bridge" {
  description = "Simulated WAN with Internet through the host NAT (no DHCP)."
  type        = string
  default     = "vmbr1"
}

variable "build_ip" {
  description = "Static address of the build VM, set through cloud-init."
  type        = string
  default     = "10.10.10.250"
}

variable "build_prefix" {
  description = "Prefix length of the build network."
  type        = number
  default     = 24
}

variable "build_gateway" {
  description = "Gateway of the build network (the Proxmox host NAT)."
  type        = string
  default     = "10.10.10.1"
}

variable "build_dns" {
  description = "DNS server used during the build."
  type        = string
  default     = "1.1.1.1"
}

variable "ssh_private_key_file" {
  description = "Lab automation key; its public half is the base template's cloud-init key."
  type        = string
}
