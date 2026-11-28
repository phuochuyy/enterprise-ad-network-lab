# Ephemeral clients for the file share access test (tests/fileserver), created and destroyed by
# scripts/fs-access-test.sh. Defined in tests/fileserver/access.yml.
locals {
  test = yamldecode(file("${path.module}/../../../tests/fileserver/access.yml"))
}

module "client" {
  source   = "../../modules/pve-vm"
  for_each = local.test.clients

  name           = each.value.name
  vm_id          = each.value.vm_id
  description    = "File share access test client - safe to delete"
  template_vm_id = local.test.template_vm_id
  os_type        = "l26"
  bios           = "seabios"
  cpu_cores      = 1
  memory_mb      = 512
  disks          = [{ interface = "scsi0", size_gb = 8 }]
  tags           = ["fs-test"]

  network_devices = [{ bridge = each.value.bridge, vlan_id = each.value.vlan }]

  cloud_init = {
    type      = "nocloud"
    ipv4_cidr = "dhcp" # DNS from DHCP = the DCs: needed to resolve the namespace
    username  = "ansible"
    ssh_keys  = var.lab_ssh_public_key == "" ? [] : [trimspace(var.lab_ssh_public_key)]
  }
}

output "clients" {
  description = "Client name -> VMID."
  value       = { for k, m in module.client : k => m.vm_id }
}
