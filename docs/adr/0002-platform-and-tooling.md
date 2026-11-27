# ADR-0002: Platform and tooling choices

- Status: Accepted
- Date: 2026-11-27

## Context

The lab must reproduce a typical Vietnamese mid-size enterprise (Windows-centric, two sites) on a
single laptop: Intel i7-11800H (16 threads), 23 GB RAM, 512 GB NVMe, Proxmox VE 9.3, Wi-Fi uplink
behind a NAT bridge (`vmbr1`, 10.10.10.0/24). The job targets Windows Server, VMware/Hyper-V,
firewalls/VPN, backup and monitoring.

## Decision

| Concern | Choice | Why | Rejected |
| --- | --- | --- | --- |
| Hypervisor (outer) | Proxmox VE | Already installed; API + nested virtualization | — |
| Hypervisor (skill target) | Hyper-V (nested, in companion repo) | Fits RAM; Windows-native like the target environment | VMware vSphere: vCenter alone needs ~14 GB RAM |
| Provisioning | Terraform `bpg/proxmox` | Maintained, full API coverage, declarative | Telmate provider (less active), manual `qm` |
| Images | Packer `proxmox-iso` | Repeatable golden images, unattended | Hand-built templates |
| Configuration | Ansible (`microsoft.ad`, `ansible.windows`) over WinRM | Agentless, idempotent, readable | DSC-only, GPO-only |
| Firewall / router | OPNsense | Open source, enterprise features (VLAN, WireGuard, HA), API | pfSense CE (slower release cadence) |
| Access to Proxmox | API token `terraform@pve!tf` with a least-privilege role | No root/sudo in automation, auditable, revocable | root@pam password |
| Evidence | scrot, ffmpeg (x11grab), asciinema | Scriptable, lightweight | OBS (manual) |

## Consequences

- Windows guests use 180-day evaluation media; templates are rebuilt rather than re-armed.
- WAN/Internet for both sites is simulated on `vmbr1`; no public exposure.
- RAM is the binding constraint: lab profiles start/stop VM groups by tag (see `docs/architecture.md`).
