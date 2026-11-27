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
