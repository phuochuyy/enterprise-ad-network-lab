# Module `pve-vm`

Opinionated Proxmox VE virtual machine for this lab (and its companion repos), built on
[`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest).

- Full-clone from a Packer template **or** boot an installer ISO
- q35 + virtio-scsi-single, iothread, discard/SSD emulation on every disk
- OVMF with pre-enrolled Secure Boot keys for Windows, optional TPM 2.0
- Optional cloud-init (static or DHCP) for Linux templates
- Tags sorted and always include `terraform`; hostname convention enforced (`hq-dc01`)

## Usage

```hcl
module "hq_dc01" {
  source = "git::https://github.com/phuochuyy/enterprise-ad-network-lab.git//terraform/modules/pve-vm?ref=v1.0.0"

  name           = "hq-dc01"
  vm_id          = 201
  template_vm_id = 9001 # tpl-ws2022-core
  os_type        = "win11"
  cpu_cores      = 2
  memory_mb      = 2560
  tags           = ["lab-core", "site-hq"]

  network_devices = [{ bridge = "vmbr10", vlan_id = 20 }]
}
```

Installer-based VM (e.g. OPNsense):

```hcl
module "hq_fw01" {
  source      = "../../modules/pve-vm"
  name        = "hq-fw01"
  vm_id       = 101
  iso_file_id = "local:iso/OPNsense-dvd-amd64.iso"
  os_type     = "other"
  bios        = "seabios"
  network_devices = [
    { bridge = "vmbr1" },  # WAN
    { bridge = "vmbr10" }, # LAN trunk (VLANs on the firewall)
  ]
}
```

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | — | `<site>-<role><nn>` |
| `vm_id` | number | — | VMID (100–9999) |
| `network_devices` | list(object) | — | `bridge`, optional `vlan_id`, `model` (virtio) |
| `template_vm_id` | number | `null` | Template to full-clone |
| `iso_file_id` | string | `null` | Installer ISO |
| `cpu_cores` / `cpu_type` | number / string | `2` / `host` | `host` enables nested virtualization |
| `memory_mb` / `memory_min_mb` | number | `2048` / `0` | `0` = no ballooning |
| `os_type` | string | `l26` | `l26`, `win10`, `win11`, `other` |
| `bios` | string | `ovmf` | `ovmf` or `seabios` |
| `tpm` | bool | `false` | TPM 2.0 |
| `disks` | list(object) | `[{scsi0, 32}]` | `interface`, `size_gb` |
| `datastore_id` | string | `local-lvm` | Disks, EFI, TPM |
| `cloud_init` | object | `null` | `ipv4_cidr` (or `dhcp`), `gateway`, `dns_servers`, `dns_domain`, `username`, `ssh_keys` |
| `tags`, `description`, `node_name` | | | Metadata / placement |
| `started`, `on_boot`, `startup_order`, `agent_enabled` | | | Lifecycle |

## Outputs

`vm_id`, `name`, `mac_addresses`, `ipv4_addresses` (from the guest agent).

## Tests

```bash
cd terraform/modules/pve-vm
terraform init -backend=false
terraform test   # 6 plan-only runs against a mocked provider
```
