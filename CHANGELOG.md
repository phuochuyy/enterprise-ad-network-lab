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

### Fixed

- Windows clones hung at first boot: the specialize pass rejected the answer file (inline command over the 259-char `Path` limit) - see [RCA](docs/rca/2026-11-28-ws2022-clone-hang.md)
- Windows clones kept a `WIN-XXXX` name: hostname is now read from Proxmox user_data
- Windows 11 clones unreachable: WinRM delayed start, Public network profile, and OOBE renaming the machine to `DESKTOP-XXXX`
