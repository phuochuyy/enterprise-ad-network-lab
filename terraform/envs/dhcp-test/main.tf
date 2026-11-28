# Ephemeral DHCP clients for the DHCP failover test (tests/dhcp), created and destroyed by
# scripts/dhcp-failover-test.sh. Defined in tests/dhcp/failover.yml.
locals {
  test = yamldecode(file("${path.module}/../../../tests/dhcp/failover.yml"))
}

module "client" {
  source   = "../../modules/pve-vm"
  for_each = local.test.clients

  name           = each.value.name
  vm_id          = each.value.vm_id
  description    = "DHCP failover test client - safe to delete"
  template_vm_id = local.test.template_vm_id
  os_type        = "l26"
  bios           = "seabios"
  cpu_cores      = 1
  memory_mb      = 512
  disks          = [{ interface = "scsi0", size_gb = 8 }]
  tags           = ["dhcp-test"]

  network_devices = [{ bridge = each.value.bridge, vlan_id = each.value.vlan }]

  cloud_init = {
    type      = "nocloud"
    ipv4_cidr = "dhcp" # the point of the test: address, router and DNS come from the DCs
    username  = "ansible"
    ssh_keys  = var.lab_ssh_public_key == "" ? [] : [trimspace(var.lab_ssh_public_key)]
  }
}

output "clients" {
  description = "Client name -> VMID."
  value       = { for k, m in module.client : k => m.vm_id }
}
