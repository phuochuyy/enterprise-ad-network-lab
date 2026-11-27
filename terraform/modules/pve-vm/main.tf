locals {
  # Tags are stored sorted by Proxmox; sorting here avoids a perpetual diff.
  tags = sort(distinct(concat(["terraform"], var.tags)))
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.description
  tags        = local.tags

  started = var.started
  on_boot = var.on_boot

  machine       = "q35"
  bios          = var.bios
  scsi_hardware = "virtio-scsi-single"

  dynamic "clone" {
    for_each = var.template_vm_id == null ? [] : [var.template_vm_id]
    content {
      vm_id = clone.value
      full  = true
    }
  }

  dynamic "cdrom" {
    for_each = var.iso_file_id == null ? [] : [var.iso_file_id]
    content {
      file_id   = cdrom.value
      interface = "ide2"
    }
  }

  agent {
    enabled = var.agent_enabled
    trim    = true
  }

  cpu {
    cores = var.cpu_cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.memory_min_mb
  }

  operating_system {
    type = var.os_type
  }

  dynamic "efi_disk" {
    for_each = var.bios == "ovmf" ? [1] : []
    content {
      datastore_id      = var.datastore_id
      type              = "4m"
      pre_enrolled_keys = var.os_type == "win11"
    }
  }

  dynamic "tpm_state" {
    for_each = var.tpm ? [1] : []
    content {
      datastore_id = var.datastore_id
      version      = "v2.0"
    }
  }

  dynamic "disk" {
    for_each = var.disks
    content {
      datastore_id = var.datastore_id
      interface    = disk.value.interface
      size         = disk.value.size_gb
      file_format  = "raw"
      iothread     = true
      discard      = "on"
      ssd          = true
    }
  }

  dynamic "network_device" {
    for_each = var.network_devices
    content {
      bridge   = network_device.value.bridge
      vlan_id  = network_device.value.vlan_id
      model    = network_device.value.model
      firewall = false
    }
  }

  dynamic "startup" {
    for_each = var.startup_order == null ? [] : [var.startup_order]
    content {
      order    = startup.value
      up_delay = 30
    }
  }

  dynamic "initialization" {
    for_each = var.cloud_init == null ? [] : [var.cloud_init]
    content {
      datastore_id = var.datastore_id

      ip_config {
        ipv4 {
          address = initialization.value.ipv4_cidr
          gateway = initialization.value.ipv4_cidr == "dhcp" ? null : initialization.value.gateway
        }
      }

      dns {
        servers = initialization.value.dns_servers
        domain  = initialization.value.dns_domain
      }

      user_account {
        username = initialization.value.username
        keys     = initialization.value.ssh_keys
      }
    }
  }

  lifecycle {
    # Installers eject their ISO; Windows sysprep rewrites the description - neither is drift we care about.
    ignore_changes = [cdrom, description]
  }
}
