# Windows golden templates on Proxmox: Server 2022 (Core / Desktop) and Windows 11.
# One source, parameterised per template via vars/*.pkrvars.hcl. Run through scripts/packer.sh.

locals {
  cbi_root = "C:/Program Files/Cloudbase Solutions/Cloudbase-Init"

  answer_vars = {
    image_index    = var.image_index
    driver_dir     = var.driver_dir
    admin_password = var.admin_password
    timezone       = var.timezone
    is_client      = var.is_client
  }
}

source "proxmox-iso" "windows" {
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true # loopback to the host's self-signed API cert

  vm_id                = var.template_vm_id
  vm_name              = var.template_name
  template_description = "Packer ${packer.version} · ${var.template_name} · built ${timestamp()} · cloudbase-init + WinRM HTTPS on first boot"
  tags                 = "packer;template;windows"

  os      = "win11"
  bios    = "ovmf"
  machine = "q35"

  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  tpm_config {
    tpm_storage_pool = var.storage_pool
    tpm_version      = "v2.0"
  }

  cpu_type           = "host"
  sockets            = 1
  cores              = var.cores
  memory             = var.memory_mb
  ballooning_minimum = 0

  scsi_controller = "virtio-scsi-single"
  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.storage_pool
    format       = "raw"
    io_thread    = true
    discard      = true
    ssd          = true
  }

  network_adapters {
    bridge   = var.build_bridge
    model    = "virtio"
    firewall = false
  }

  # CD drives: sata0 installer, sata1 virtio drivers, sata2 answer files.
  boot_iso {
    type     = "sata"
    index    = 0
    iso_file = var.iso_file
    unmount  = true
  }

  additional_iso_files {
    type     = "sata"
    index    = 1
    iso_file = var.virtio_iso_file
    unmount  = true
  }

  additional_iso_files {
    type             = "sata"
    index            = 2
    iso_storage_pool = "local"
    cd_label         = "UNATTEND"
    unmount          = true
    cd_content = {
      "autounattend.xml" = templatefile("${path.root}/answer/autounattend.xml.pkrtpl", local.answer_vars)
      "bootstrap.ps1" = templatefile("${path.root}/answer/bootstrap.ps1.pkrtpl", {
        build_ip      = var.build_ip
        build_prefix  = var.build_prefix
        build_gateway = var.build_gateway
        build_dns     = var.build_dns
      })
    }
  }

  boot = "order=scsi0;sata0"
  # OVMF shows "Press any key to boot from CD or DVD" for a few seconds.
  boot_wait    = "3s"
  boot_command = ["<enter><wait1s><enter><wait1s><enter><wait1s><enter>"]

  qemu_agent = true

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_host     = var.build_ip
  winrm_port     = 5985
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "1h" # install ~15 min; fail fast if bootstrap breaks
}

build {
  name    = "windows"
  sources = ["source.proxmox-iso.windows"]

  provisioner "powershell" {
    environment_vars = [
      "CBI_URL=${var.cloudbase_init_url}",
      "CBI_SHA256=${var.cloudbase_init_sha256}",
    ]
    script = "${path.root}/scripts/install-cloudbase-init.ps1"
  }

  provisioner "file" {
    source      = "${path.root}/cloudbase-init/conf/"
    destination = "${local.cbi_root}/conf/"
  }

  provisioner "file" {
    source      = "${path.root}/cloudbase-init/LocalScripts/"
    destination = "${local.cbi_root}/LocalScripts/"
  }

  provisioner "file" {
    content     = templatefile("${path.root}/answer/unattend-sysprep.xml.pkrtpl", local.answer_vars)
    destination = "${local.cbi_root}/conf/Unattend.xml"
  }

  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/cleanup.ps1"
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/sysprep.ps1"
  }

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
