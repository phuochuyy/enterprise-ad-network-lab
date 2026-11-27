output "site_bridges" {
  description = "Site trunk bridges created on the Proxmox host."
  value       = { for k, b in proxmox_network_linux_bridge.site : k => b.comment }
}

output "image_file_ids" {
  description = "Volume IDs of installer media, e.g. local:iso/OPNsense-26.7-dvd-amd64.iso."
  value       = { for k, f in proxmox_download_file.image : k => f.id }
}
