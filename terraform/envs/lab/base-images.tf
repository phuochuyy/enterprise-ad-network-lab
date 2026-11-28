# Base template straight from the Ubuntu cloud image (no changes inside the guest). Packer
# (packer/ubuntu, proxmox-clone) clones it, adds qemu-guest-agent and updates, and produces the
# real golden template 9004 tpl-ubuntu-2404. Kept separate so the cloud image is imported once.
resource "proxmox_virtual_environment_vm" "ubuntu_base" {
  name        = "base-ubuntu-2404-cloudimg"
  vm_id       = 9100
  node_name   = var.node_name
  description = "Unmodified Ubuntu 24.04 cloud image - source for packer/ubuntu only"
  tags        = ["base-image", "terraform", "ubuntu"]
  template    = true
  started     = false

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  agent {
    enabled = true # the agent itself is installed by Packer; the flag is inherited by clones
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 1024
  }

  operating_system {
    type = "l26"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    import_from  = proxmox_download_file.image["ubuntu2404"].id
    size         = 8
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge   = "vmbr1"
    model    = "virtio"
    firewall = false
  }

  # Cloud images log to the serial console; without a serial port early boot output is lost.
  serial_device {}

  initialization {
    datastore_id = "local-lvm"
    type         = "nocloud"
    user_account {
      username = "ansible"
      keys     = [trimspace(file(pathexpand("~/.config/lab/id_ed25519.pub")))]
    }
    ip_config {
      ipv4 {
        address = "dhcp" # overridden by Packer and by every clone
      }
    }
  }

  lifecycle {
    ignore_changes = [description]
  }
}
