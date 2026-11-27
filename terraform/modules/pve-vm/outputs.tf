output "vm_id" {
  description = "Proxmox VMID of the VM."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "Hostname of the VM."
  value       = proxmox_virtual_environment_vm.this.name
}

output "mac_addresses" {
  description = "MAC address of each NIC, in the order of var.network_devices (useful for DHCP reservations)."
  value       = proxmox_virtual_environment_vm.this.mac_addresses
}

output "ipv4_addresses" {
  description = "IPv4 addresses reported by the guest agent (empty until the agent is running)."
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}
