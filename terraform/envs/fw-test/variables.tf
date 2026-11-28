variable "pve_endpoint" {
  description = "Proxmox API endpoint."
  type        = string
  default     = "https://127.0.0.1:8006/"
}

variable "pve_insecure" {
  description = "Skip TLS verification (loopback to the host's self-signed cert)."
  type        = bool
  default     = true
}

variable "lab_ssh_public_key" {
  description = "Lab automation public key (scripts/tf.sh); lets an operator SSH into a probe kept with KEEP=1."
  type        = string
  default     = ""
}
