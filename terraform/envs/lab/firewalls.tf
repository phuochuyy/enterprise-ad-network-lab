# Site firewalls, cloned from the Packer template tpl-opnsense (9005).
# NIC order is fixed by the template: net0 = LAN (site trunk, VLANs live in OPNsense), net1 = WAN.
# Terraform owns the VM only. The firewall config is rendered and pushed by Ansible
# (ansible/playbooks/firewalls.yml): first the WAN identity through the guest agent, then the
# full config.xml over SSH.
locals {
  firewalls = {
    hq-fw01 = { vm_id = 101, trunk = "vmbr10", cores = 2, site = "site-hq", profile = "lab-core" }
    br-fw01 = { vm_id = 102, trunk = "vmbr20", cores = 1, site = "site-br", profile = "lab-branch" }
  }
}

module "firewall" {
  source   = "../../modules/pve-vm"
  for_each = local.firewalls

  name           = each.key
  vm_id          = each.value.vm_id
  description    = "OPNsense 26.7 - config managed by Ansible (ansible/inventory/host_vars/${each.key}.yml)"
  template_vm_id = var.opnsense_template_vm_id
  os_type        = "other"
  bios           = "seabios"
  cpu_cores      = each.value.cores
  memory_mb      = 1024
  disks          = [{ interface = "scsi0", size_gb = 16 }]
  tags           = [each.value.site, each.value.profile, "firewall"]

  network_devices = [
    { bridge = proxmox_network_linux_bridge.site[each.value.trunk].name }, # vtnet0 - LAN trunk
    { bridge = "vmbr1" },                                                  # vtnet1 - simulated WAN
  ]

  on_boot       = true
  startup_order = 1 # firewalls first: every other VM depends on them
}

output "firewalls" {
  description = "Firewall VMIDs by name."
  value       = { for k, m in module.firewall : k => m.vm_id }
}
