# Domain controllers (issue #7), cloned from tpl-ws2022-core (9001). cloudbase-init applies the
# hostname and static IP from the configdrive2 drive; Ansible (playbooks/ad.yml) promotes them.
# DNS starts on the site firewall (Unbound) and is switched to the DCs once AD DNS exists.
locals {
  domain_controllers = {
    hq-dc01 = { vm_id = 201, trunk = "vmbr10", vlan = 20, ip = "172.16.20.11", gateway = "172.16.20.1", memory_mb = 2560, site = "site-hq", profile = "lab-core" }
    br-dc01 = { vm_id = 202, trunk = "vmbr20", vlan = 120, ip = "172.17.20.11", gateway = "172.17.20.1", memory_mb = 2048, site = "site-br", profile = "lab-branch" }
  }
}

module "domain_controller" {
  source   = "../../modules/pve-vm"
  for_each = local.domain_controllers

  name           = each.key
  vm_id          = each.value.vm_id
  description    = "AD DS domain controller ${var.ad_domain} - configured by Ansible (ansible/playbooks/ad.yml)"
  template_vm_id = var.ws2022_core_template_vm_id
  os_type        = "win11" # Proxmox's type for Windows 11 / Server 2022
  cpu_cores      = 2
  memory_mb      = each.value.memory_mb
  disks          = [{ interface = "scsi0", size_gb = 40 }]
  tags           = [each.value.site, each.value.profile, "dc"]

  network_devices = [{ bridge = proxmox_network_linux_bridge.site[each.value.trunk].name, vlan_id = each.value.vlan }]

  cloud_init = {
    type        = "configdrive2" # cloudbase-init (Windows)
    ipv4_cidr   = "${each.value.ip}/24"
    gateway     = each.value.gateway
    dns_servers = [each.value.gateway]
  }

  on_boot       = true
  startup_order = 2 # after the firewalls
  depends_on    = [module.firewall]
}

output "domain_controllers" {
  description = "Domain controller VMIDs by name."
  value       = { for k, m in module.domain_controller : k => m.vm_id }
}
