# Ephemeral probe VMs for the firewall policy test (tests/firewall). One small Ubuntu clone per
# VLAN, created and destroyed by scripts/fw-policy-test.sh. Probes are defined once, in
# tests/firewall/policy.yml, and read here.
locals {
  policy = yamldecode(file("${path.module}/../../../tests/firewall/policy.yml"))
}

module "probe" {
  source   = "../../modules/pve-vm"
  for_each = local.policy.probes

  name           = each.value.name
  vm_id          = each.value.vm_id
  description    = "Firewall policy test probe - safe to delete"
  template_vm_id = local.policy.template_vm_id
  os_type        = "l26"
  bios           = "seabios"
  cpu_cores      = 1
  memory_mb      = 512
  disks          = [{ interface = "scsi0", size_gb = 8 }]
  tags           = ["fw-test"]

  network_devices = [{ bridge = each.value.bridge, vlan_id = try(each.value.vlan, null) }]

  cloud_init = {
    type        = "nocloud"
    ipv4_cidr   = "${each.value.ip}/24"
    gateway     = each.value.gateway
    dns_servers = [try(each.value.dns, each.value.gateway)]
    username    = "ansible"
    ssh_keys    = var.lab_ssh_public_key == "" ? [] : [trimspace(var.lab_ssh_public_key)]
  }
}

output "probes" {
  description = "Probe name -> VMID."
  value       = { for k, m in module.probe : k => m.vm_id }
}
