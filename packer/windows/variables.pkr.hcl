# Proxmox connection comes from the environment (scripts/packer.sh):
# PROXMOX_URL, PROXMOX_USERNAME (token id), PROXMOX_TOKEN.

variable "proxmox_node" {
  description = "Proxmox node to build on."
  type        = string
  default     = "pve"
}

# --- Template identity -------------------------------------------------------
variable "template_vm_id" {
  description = "VMID of the resulting template (9xxx)."
  type        = number
}

variable "template_name" {
  description = "Template name, e.g. tpl-ws2022-core."
  type        = string
}

variable "image_index" {
  description = "WIM image index on the install ISO (WS2022 eval: 1 Std Core, 2 Std Desktop, 3 DC Core, 4 DC Desktop; Win11 Ent eval: 1)."
  type        = number
}

variable "is_client" {
  description = "True for Windows 11: adds the local 'labadmin' account that client OOBE requires."
  type        = bool
  default     = false
}

variable "driver_dir" {
  description = "virtio-win driver folder for this OS: 2k22 (Server 2022) or w11 (Windows 11)."
  type        = string
}

# --- Media -------------------------------------------------------------------
variable "iso_file" {
  description = "Windows install ISO volume id."
  type        = string
}

variable "virtio_iso_file" {
  description = "virtio-win ISO volume id."
  type        = string
  default     = "local:iso/virtio-win-0.1.302.iso"
}

# --- Hardware ----------------------------------------------------------------
variable "cores" {
  description = "vCPU cores used for the build."
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM for the build (Windows 11 requires >= 4096)."
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "System disk size (Windows 11 requires >= 64G)."
  type        = string
  default     = "40G"
}

variable "storage_pool" {
  description = "Datastore for disks, EFI vars and TPM state."
  type        = string
  default     = "local-lvm"
}

# --- Build network (vmbr1 has no DHCP) ---------------------------------------
variable "build_bridge" {
  description = "Bridge with Internet access used only during the build."
  type        = string
  default     = "vmbr1"
}

variable "build_ip" {
  description = "Temporary static IP of the build VM; removed by sysprep."
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

# --- Guest settings ----------------------------------------------------------
variable "admin_password" {
  description = "Local Administrator password baked into the template (PKR_VAR_admin_password)."
  type        = string
  sensitive   = true
}

variable "timezone" {
  description = "Windows time zone id."
  type        = string
  default     = "SE Asia Standard Time"
}

variable "cloudbase_init_url" {
  description = "cloudbase-init MSI (configures hostname/network from the Proxmox cloud-init drive on clones)."
  type        = string
  default     = "https://github.com/cloudbase/cloudbase-init/releases/download/1.1.9/CloudbaseInitSetup_1_1_9_x64.msi"
}

variable "cloudbase_init_sha256" {
  description = "Expected SHA-256 of the cloudbase-init MSI; the install script refuses a mismatch."
  type        = string
  default     = "ffbf80515a7311ed00800276a6af7aab23b41d7acf13e79ce3d2d56844f638f7"
}
