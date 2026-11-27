# ---------------------------------------------------------------------------
# Identity & placement
# ---------------------------------------------------------------------------
variable "name" {
  description = "Hostname of the VM, `<site>-<role><nn>` (e.g. hq-dc01)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}-[a-z]+[0-9]{2}$", var.name))
    error_message = "Name must follow <site>-<role><nn>, lowercase (e.g. hq-dc01)."
  }
}

variable "vm_id" {
  description = "Proxmox VMID. Ranges: 1xx network, 2xx identity/services, 3xx virtualization, 4xx ops, 9xxx templates."
  type        = number

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 9999
    error_message = "vm_id must be between 100 and 9999."
  }
}

variable "node_name" {
  description = "Proxmox node that hosts the VM."
  type        = string
  default     = "pve"
}

variable "description" {
  description = "Free-text description shown in the Proxmox UI (Markdown supported)."
  type        = string
  default     = "Managed by Terraform"
}

variable "tags" {
  description = "Proxmox tags, e.g. [\"lab-core\", \"site-hq\"]. Used by lab profiles to start/stop groups."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Source: clone a template OR boot an installer ISO
# ---------------------------------------------------------------------------
variable "template_vm_id" {
  description = "VMID of the template to full-clone. Null = create an empty VM (use iso_file_id to install)."
  type        = number
  default     = null
}

variable "iso_file_id" {
  description = "ISO to attach as CD-ROM, e.g. local:iso/OPNsense-25.7-dvd-amd64.iso. Null = no CD-ROM."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Hardware
# ---------------------------------------------------------------------------
variable "cpu_cores" {
  description = "Number of vCPU cores."
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "CPU model. `host` is required for nested virtualization (Hyper-V)."
  type        = string
  default     = "host"
}

variable "memory_mb" {
  description = "Maximum RAM in MiB."
  type        = number
  default     = 2048
}

variable "memory_min_mb" {
  description = "Ballooning floor in MiB. 0 disables ballooning (recommended for DCs and firewalls)."
  type        = number
  default     = 0
}

variable "os_type" {
  description = "Guest OS type hint: l26 (Linux), win11 (Windows 11 / Server 2022), other (BSD, e.g. OPNsense)."
  type        = string
  default     = "l26"

  validation {
    condition     = contains(["l26", "win10", "win11", "other"], var.os_type)
    error_message = "os_type must be one of l26, win10, win11, other."
  }
}

variable "bios" {
  description = "Firmware: seabios (legacy) or ovmf (UEFI, required for Windows 11 / Secure Boot)."
  type        = string
  default     = "ovmf"

  validation {
    condition     = contains(["seabios", "ovmf"], var.bios)
    error_message = "bios must be seabios or ovmf."
  }
}

variable "tpm" {
  description = "Attach a virtual TPM 2.0 (needed by Windows 11)."
  type        = bool
  default     = false
}

variable "datastore_id" {
  description = "Datastore for disks, EFI vars and TPM state."
  type        = string
  default     = "local-lvm"
}

variable "disks" {
  description = "Disks to attach. The first one (scsi0) is the boot disk; when cloning, its size can only grow."
  type = list(object({
    interface = string
    size_gb   = number
  }))
  default = [{ interface = "scsi0", size_gb = 32 }]

  validation {
    condition     = length(var.disks) > 0 && alltrue([for d in var.disks : can(regex("^(scsi|virtio|sata)[0-9]+$", d.interface))])
    error_message = "At least one disk is required; interface must look like scsi0, virtio1 or sata0."
  }
}

variable "network_devices" {
  description = "NICs in order. vlan_id = null for untagged; model e1000e only for guests without virtio drivers."
  type = list(object({
    bridge  = string
    vlan_id = optional(number)
    model   = optional(string, "virtio")
  }))
}

# ---------------------------------------------------------------------------
# Lifecycle & guest integration
# ---------------------------------------------------------------------------
variable "started" {
  description = "Start the VM after creation."
  type        = bool
  default     = true
}

variable "on_boot" {
  description = "Start the VM when the Proxmox host boots."
  type        = bool
  default     = false
}

variable "startup_order" {
  description = "Boot order among on_boot VMs (firewalls first, then DCs, then members). Null = unordered."
  type        = number
  default     = null
}

variable "agent_enabled" {
  description = "Enable the QEMU guest agent (the template must have it installed)."
  type        = bool
  default     = true
}

variable "cloud_init" {
  description = <<-EOT
    Cloud-init drive. Null = none. Linux templates use type "nocloud" and set username;
    Windows templates (cloudbase-init) need type "configdrive2" and no username.
    (An explicit null on an optional attribute with a default is replaced by the default,
    so username has no default: omit it to create no user.)
  EOT
  type = object({
    type        = optional(string, "nocloud")
    ipv4_cidr   = string # e.g. 172.16.20.61/24 or "dhcp"
    gateway     = optional(string)
    dns_servers = optional(list(string), [])
    dns_domain  = optional(string)
    username    = optional(string)
    ssh_keys    = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.cloud_init == null || contains(["nocloud", "configdrive2"], try(var.cloud_init.type, "nocloud"))
    error_message = "cloud_init.type must be nocloud or configdrive2."
  }
}
