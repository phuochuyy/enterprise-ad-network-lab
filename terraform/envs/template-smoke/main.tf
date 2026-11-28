# Template acceptance test: clone a template onto the build network with a static IP from
# cloud-init, then scripts/smoke-test.sh checks hostname, IP and WinRM HTTPS before destroying it.
module "smoke" {
  source = "../../modules/pve-vm"

  name           = "hq-tst01"
  vm_id          = 999
  description    = "Template smoke test - safe to delete"
  template_vm_id = var.template_vm_id
  os_type        = var.os_type
  tpm            = var.tpm
  memory_mb      = 4096
  disks          = [{ interface = "scsi0", size_gb = var.disk_gb }]
  tags           = ["smoke-test"]

  network_devices = [{ bridge = "vmbr1" }]

  cloud_init = {
    type        = "configdrive2"
    ipv4_cidr   = "${var.test_ip}/24"
    gateway     = "10.10.10.1"
    dns_servers = ["1.1.1.1"]
  }
}

output "vm_id" {
  description = "VMID of the smoke-test clone."
  value       = module.smoke.vm_id
}
