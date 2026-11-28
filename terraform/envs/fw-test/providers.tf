# Credentials are never in code: scripts/tf.sh exports PROXMOX_VE_API_TOKEN
# from ~/.config/pve/terraform-token.json (token terraform@pve!tf, role TerraformProv).
provider "proxmox" {
  endpoint = var.pve_endpoint
  insecure = var.pve_insecure
}
