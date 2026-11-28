# ADR-0004: OPNsense build and configuration as code

- Status: Accepted
- Date: 2026-11-28

## Context

Both sites need an OPNsense firewall (issue #5) that is rebuilt from code, with no clicking in the
web GUI and no console session. Constraints found while building it:

- The stock installer is a series of `bsddialog` prompts, and nothing watches the console during
  automated builds.
- A fresh clone has no WAN address, so it cannot be reached over the network.
- On FreeBSD the QEMU guest agent times out on `guest-file-write` above about 4 KB, so a full
  `config.xml` (about 20 KB) cannot be written through it.
- Interface assignment and VLANs are not exposed by the OPNsense REST API.

## Decision

1. **Template `tpl-opnsense-26.7` (9005) built by Packer from the stock DVD.**
   - The console receives one line (`root` / menu 8 / run the seed script). Everything else is
     `packer/opnsense/seed/install.sh`, which replays the stock "Install (UFS)" steps
     (`scriptedpart`, `mount`, `opnsense-install`, `bootconfig`) without dialogs.
   - The script pushes its log to the host, so failures are visible without a console.
   - The template then gets the guest agent plugin and boots with no WAN address.
2. **Terraform owns the VM; Ansible owns the configuration.**
   - `terraform/envs/lab/firewalls.tf` clones the template.
   - `ansible/roles/opnsense` renders a complete `config.xml` from inventory data (VLANs,
     aliases, rules) and installs it. Rules are data in `host_vars/<fw>.yml`, so a policy change
     is a reviewable YAML diff.
3. **Two management channels.**
   - *Out of band*, once per fresh clone: through the Proxmox guest-agent API, set the WAN
     address and stop pf. This is a single short command, which stays under the agent's size limit.
   - *In band*, always after that: SSH to the WAN address (key-only, from the admin host only).
     `template` validates the XML with PHP before replacing `/conf/config.xml`, then the box reboots.
4. **Evidence is generated, not screenshotted.**
   - `playbooks/firewalls-export.yml` commits a sanitized export of the running config
     (`docs/network/opnsense/`).
   - Automated connectivity tests prove the deny-by-default policy.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Click through the GUI, export a backup | Not reproducible, not reviewable |
| Terraform `browningluke/opnsense` provider / REST API only | Cannot assign interfaces or create the VLAN layout; would still need a bootstrap |
| OPNsense nano image + web GUI restore | The restore has to be scripted against the GUI's login and CSRF tokens, which is brittle |
| Packer typing through the installer menus | Many blind keystrokes, and menus change between releases |

## Consequences

- OPNsense's model migrations fill in defaults on every boot. The running config is therefore a
  superset of the rendered one, and drift is reviewed on the sanitized export, not by
  byte-comparing files.
- Any config change reboots the firewall (~1 min). This is acceptable in the lab; a production
  setup would reload services selectively, or use a CARP pair.
- The root password is a deterministic SHA-512 crypt hash (salt derived from the hostname), so
  runs are idempotent. The secret itself stays in `~/.config/lab/secrets.json`.
