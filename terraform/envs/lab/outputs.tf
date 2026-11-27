output "site_bridges" {
  description = "Site trunk bridges created on the Proxmox host."
  value       = { for k, b in proxmox_network_linux_bridge.site : k => b.comment }
}
