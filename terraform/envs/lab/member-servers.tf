# Domain member servers, cloned from tpl-ws2022-core (9001) and joined by Ansible
# (playbooks/members.yml). hq-fs01: file server and DFS namespace server (issue #9), with a
# separate data disk for the shares.
locals {
  member_servers = {
    hq-fs01 = {
      vm_id     = 211, trunk = "vmbr10", vlan = 20, ip = "172.16.20.21", gateway = "172.16.20.1",
      memory_mb = 2048, data_disk_gb = 20, site = "site-hq", profile = "lab-core", role = "fileserver"
    }
  }
}

module "member_server" {
  source   = "../../modules/pve-vm"
  for_each = local.member_servers

  name           = each.key
  vm_id          = each.value.vm_id
  description    = "Member server ${var.ad_domain} - configured by Ansible"
  template_vm_id = var.ws2022_core_template_vm_id
  os_type        = "win11"
  cpu_cores      = 2
  memory_mb      = each.value.memory_mb
  disks = concat(
    [{ interface = "scsi0", size_gb = 40 }],
    each.value.data_disk_gb > 0 ? [{ interface = "scsi1", size_gb = each.value.data_disk_gb }] : []
  )
  tags = [each.value.site, each.value.profile, each.value.role]

  network_devices = [{ bridge = proxmox_network_linux_bridge.site[each.value.trunk].name, vlan_id = each.value.vlan }]

  cloud_init = {
    type        = "configdrive2"
    ipv4_cidr   = "${each.value.ip}/24"
    gateway     = each.value.gateway
    dns_servers = [each.value.gateway] # switched to the DCs by Ansible before the domain join
  }

  on_boot       = true
  startup_order = 3 # after firewalls and DCs
  depends_on    = [module.domain_controller]
}

output "member_servers" {
  description = "Member server VMIDs by name."
  value       = { for k, m in module.member_server : k => m.vm_id }
}
