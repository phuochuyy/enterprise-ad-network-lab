# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- Terraform module `pve-vm` (clone or ISO install, OVMF/TPM, cloud-init) with 6 mocked-provider unit tests
- Lab environment `terraform/envs/lab`: VLAN-aware site trunks `vmbr10` (HQ) and `vmbr20` (Branch)
- `scripts/tf.sh`: runs Terraform with the API token loaded from a chmod-600 file
- CI job `terraform-test`
- Repository bootstrap: pre-commit (gitleaks, terraform, yamllint, markdownlint, shellcheck), CI lint workflow
- Issue / PR templates, including an incident (RCA) template
- Evidence capture scripts: `scripts/media/shot.sh`, `rec.sh`, `cast.sh`
- ADR-0001 (record decisions), ADR-0002 (platform and tooling)
- Network & IP design (`docs/architecture.md`) and ADR-0003 (addressing, naming, AD domain name)
- Packer Windows templates (Server 2022 Core/Desktop, Windows 11) with cloudbase-init and WinRM HTTPS on first boot
- `pve-vm`: configdrive2 and user-less cloud-init for Windows clones
- `scripts/smoke-test.sh`: clone-boot-verify acceptance test for templates (env `terraform/envs/template-smoke`)
- `scripts/diag/win-offline-logs.sh`: read-only Setup/cloudbase-init log pull from a stopped VM's disk
- Lint hook `check-unattend`: answer-file command lengths within Windows Setup limits
- OPNsense template `tpl-opnsense-26.7` (Packer, unattended install from the stock DVD, QEMU guest agent)
- Site firewalls `hq-fw01` / `br-fw01`: VLANs 10/20/30/40 (HQ) and 120/130 (Branch), deny-by-default rules, config as code (Ansible role `opnsense`, ADR-0004)
- Sanitized exports of the running firewall configs (`docs/network/opnsense/`, `scripts/opnsense-sanitize.py`)
- CI: `packer-validate` for OPNsense, `ansible-lint` (production profile)
- Ubuntu 24.04 template `tpl-ubuntu-2404` with qemu-guest-agent (Packer `proxmox-clone` of the Terraform-imported cloud image `base-ubuntu-2404-cloudimg`)
- `scripts/smoke-test.sh linux`: cloud-init hostname/IP/SSH key, cloud-init done, guest agent answering the Proxmox API
- WireGuard site-to-site HQ <-> Branch (routed, PSK) and remote-access VPN for admins on hq-fw01 (ADR-0005); handshake asserted on every converge; `scripts/lab-secrets.sh` for keys
- Firewall policy test (`scripts/fw-policy-test.sh`, `tests/firewall/policy.yml`): 57 cases: inter-VLAN, cross-site over the tunnel, WAN exposure, remote-access VPN, TCP traceroute through the tunnel; real traffic from probe VMs, report in `docs/network/policy-test-report.md`

### Fixed

- Windows clones hung at first boot: the specialize pass rejected the answer file (inline command over the 259-char `Path` limit) - see [RCA](docs/rca/2026-11-28-ws2022-clone-hang.md)
- Windows clones kept a `WIN-XXXX` name: hostname is now read from Proxmox user_data
- Windows 11 clones unreachable: WinRM delayed start, Public network profile, and OOBE renaming the machine to `DESKTOP-XXXX`
