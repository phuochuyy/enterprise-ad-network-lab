# Unit tests: `terraform test` from terraform/modules/pve-vm. No Proxmox needed (mock provider).

mock_provider "proxmox" {}

variables {
  name            = "hq-dc01"
  vm_id           = 201
  network_devices = [{ bridge = "vmbr10", vlan_id = 20 }]
}

run "windows_clone_defaults" {
  command = plan

  variables {
    template_vm_id = 9002
    os_type        = "win11"
    tags           = ["site-hq", "lab-core"]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.clone[0].vm_id == 9002 && proxmox_virtual_environment_vm.this.clone[0].full
    error_message = "Must full-clone the requested template."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.cdrom) == 0
    error_message = "No CD-ROM expected when cloning."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.efi_disk[0].pre_enrolled_keys
    error_message = "Windows on OVMF must have Secure Boot keys pre-enrolled."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.tags == tolist(["lab-core", "site-hq", "terraform"])
    error_message = "Tags must be sorted, de-duplicated and include 'terraform'."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.network_device[0].vlan_id == 20 && proxmox_virtual_environment_vm.this.network_device[0].model == "virtio"
    error_message = "NIC must be virtio on VLAN 20."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.initialization) == 0
    error_message = "Windows clones must not get a cloud-init drive."
  }
}

run "opnsense_from_iso" {
  command = plan

  variables {
    name        = "hq-fw01"
    vm_id       = 101
    iso_file_id = "local:iso/opnsense.iso"
    os_type     = "other"
    bios        = "seabios"
    network_devices = [
      { bridge = "vmbr1" },
      { bridge = "vmbr10" },
    ]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.cdrom[0].file_id == "local:iso/opnsense.iso"
    error_message = "Installer ISO must be attached."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.clone) == 0 && length(proxmox_virtual_environment_vm.this.efi_disk) == 0
    error_message = "ISO install on SeaBIOS: no clone, no EFI disk."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.network_device) == 2 && proxmox_virtual_environment_vm.this.network_device[0].vlan_id == null
    error_message = "Firewall needs untagged WAN + trunk LAN."
  }
}

run "linux_cloud_init_dhcp_drops_gateway" {
  command = plan

  variables {
    name           = "hq-lnx01"
    vm_id          = 221
    template_vm_id = 9004
    cloud_init = {
      ipv4_cidr = "dhcp"
      gateway   = "172.16.20.1"
    }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.initialization[0].ip_config[0].ipv4[0].gateway == null
    error_message = "Gateway must be omitted when using DHCP."
  }
}

run "windows11_gets_tpm" {
  command = plan

  variables {
    name           = "br-cl01"
    vm_id          = 231
    template_vm_id = 9003
    os_type        = "win11"
    tpm            = true
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.tpm_state[0].version == "v2.0"
    error_message = "Windows 11 requires TPM 2.0."
  }
}

run "rejects_bad_hostname" {
  command = plan

  variables {
    name = "DC01"
  }

  expect_failures = [var.name]
}

run "rejects_bad_disk_interface" {
  command = plan

  variables {
    disks = [{ interface = "hda", size_gb = 10 }]
  }

  expect_failures = [var.disks]
}
