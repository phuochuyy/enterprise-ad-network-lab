# Ubuntu 24.04 golden template: clone of the unmodified cloud image (9100) + qemu-guest-agent +
# updates, then reset to a clean cloud-init state so every clone configures itself from its own
# Proxmox cloud-init drive. Run through scripts/packer.sh ubuntu build.

source "proxmox-clone" "ubuntu" {
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true # loopback to the host's self-signed API cert

  clone_vm_id = var.base_vm_id
  full_clone  = true

  vm_id                = var.template_vm_id
  vm_name              = var.template_name
  template_description = "Packer ${packer.version} · ${var.template_name} · built ${timestamp()} · qemu-guest-agent, cloud-init clean"
  tags                 = "packer;template;ubuntu"

  os              = "l26"
  cpu_type        = "host"
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-single"
  serials         = ["socket"]

  network_adapters {
    bridge   = var.build_bridge
    model    = "virtio"
    firewall = false
  }

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"
  ipconfig {
    ip      = "${var.build_ip}/${var.build_prefix}"
    gateway = var.build_gateway
  }
  nameserver = var.build_dns

  qemu_agent = true

  communicator         = "ssh"
  ssh_host             = var.build_ip
  ssh_username         = "ansible" # cloud-init user of the base template
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "15m"
}

build {
  name    = "ubuntu"
  sources = ["source.proxmox-clone.ubuntu"]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo -E sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "${path.root}/scripts/provision.sh",
      "${path.root}/scripts/cleanup.sh",
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
