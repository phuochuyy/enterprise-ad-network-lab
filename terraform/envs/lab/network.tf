# Site trunks. No physical ports: traffic leaves a site only through its OPNsense,
# which tags/untags VLANs on its LAN interface (see docs/architecture.md).
locals {
  site_bridges = {
    vmbr10 = "HQ trunk - VLAN 10 mgmt, 20 servers, 30 users, 40 dmz, 50 storage, 60 live-migration"
    vmbr20 = "Branch trunk - VLAN 120 servers, 130 users"
  }
}

resource "proxmox_network_linux_bridge" "site" {
  for_each = local.site_bridges

  node_name  = var.node_name
  name       = each.key
  comment    = each.value
  vlan_aware = true
  autostart  = true
}
