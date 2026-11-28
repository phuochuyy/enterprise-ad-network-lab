# OPNsense firewall template: unattended install from the stock DVD, QEMU guest agent added,
# WAN address removed again so clones boot without one. Site firewalls are cloned from it and
# receive their full config out of band through the guest agent (network/opnsense).
# Run through scripts/packer.sh opnsense build.

locals {
  seed_vars = {
    hostname               = "opnsense-tpl"
    dns_server             = var.build_dns
    wan_prefix             = var.build_prefix
    wan_gateway            = var.build_gateway
    admin_host             = var.build_gateway
    root_password_hash     = var.root_password_hash
    ssh_authorized_key_b64 = base64encode(trimspace(var.ssh_public_key))
  }
}

source "proxmox-iso" "opnsense" {
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true # loopback to the host's self-signed API cert

  vm_id                = var.template_vm_id
  vm_name              = var.template_name
  template_description = "Packer ${packer.version} · ${var.template_name} · built ${timestamp()} · qemu-guest-agent, no WAN address"
  tags                 = "packer;template;opnsense"

  os   = "other"
  bios = "seabios" # FreeBSD's loader is not signed for the Microsoft Secure Boot keys

  cpu_type = "host"
  sockets  = 1
  cores    = 2
  memory   = var.memory_mb

  scsi_controller = "virtio-scsi-single" # disk shows up as da0
  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.storage_pool
    format       = "raw"
    io_thread    = true
    discard      = true
    ssd          = true
  }

  # Order matters: OPNsense's stock auto-assignment makes the first NIC LAN and the second WAN.
  network_adapters {
    bridge   = var.lan_bridge
    model    = "virtio"
    firewall = false
  }
  network_adapters {
    bridge   = var.build_bridge
    model    = "virtio"
    firewall = false
  }

  boot_iso {
    type     = "sata"
    index    = 0
    iso_file = var.iso_file
    unmount  = true
  }

  additional_iso_files {
    type             = "sata"
    index            = 1
    iso_storage_pool = "local"
    cd_label         = "OPNSEED"
    unmount          = true
    cd_content = {
      "install.sh" = file("${path.root}/seed/install.sh")
      "config.xml" = templatefile("${path.root}/seed/config.xml.pkrtpl", merge(local.seed_vars, { wan_ip = var.build_ip }))
    }
  }

  # Empty disk first: SeaBIOS falls through to the DVD; after install.sh reboots, the disk wins.
  boot = "order=scsi0;sata0"

  # The live DVD needs ~2-3 min (two 7 s "press any key" countdowns - importer and interface
  # assignment - must expire on their own; a key press there would start the interactive tools).
  # Then: console login, menu 8 (shell), run the seed script. Nothing else is typed.
  boot_wait = "240s"
  boot_command = [
    "root<enter><wait3>opnsense<enter><wait10>",
    "8<enter><wait5>",
    "mkdir /tmp/seed && mount_cd9660 /dev/iso9660/OPNSEED /tmp/seed && sh /tmp/seed/install.sh<enter>",
  ]

  qemu_agent = true

  communicator         = "ssh"
  ssh_host             = var.build_ip
  ssh_username         = "root"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "30m"
}

build {
  name    = "opnsense"
  sources = ["source.proxmox-iso.opnsense"]

  provisioner "shell" {
    inline = [
      "opnsense-version",
      "pkg update -f",
      "pkg install -y os-qemu-guest-agent", # enabled by default (model default Enabled=1)
    ]
  }

  # Final template config: same as the seed but without the build WAN address, so clones boot
  # with no WAN IP and never collide; each one gets its identity through the guest agent.
  provisioner "file" {
    content     = templatefile("${path.root}/seed/config.xml.pkrtpl", merge(local.seed_vars, { wan_ip = "" }))
    destination = "/tmp/config.final.xml"
  }

  provisioner "shell" {
    inline = [
      "pkg clean -ay",
      "rm -f /conf/sshd/*",   # host keys: every clone generates its own on first boot
      "rm -f /conf/backup/*", # config history of the build
      "rm -f /var/log/*.log /var/log/*/*.log",
      "cp /tmp/config.final.xml /conf/config.xml && rm /tmp/config.final.xml",
      "sync",
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
