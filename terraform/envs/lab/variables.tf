variable "pve_endpoint" {
  description = "Proxmox API endpoint."
  type        = string
  default     = "https://127.0.0.1:8006/"
}

variable "pve_insecure" {
  description = "Skip TLS verification. True only because the lab talks to the host's self-signed cert over loopback."
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Proxmox node name."
  type        = string
  default     = "pve"
}
