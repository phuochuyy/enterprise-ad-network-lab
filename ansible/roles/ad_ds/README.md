# Role `ad_ds`

AD DS for the lab forest `corp.huylab.internal` (issue #7, ADR-0003). Driven by
`playbooks/ad.yml`, which includes the task files in this order:

| Task file | Runs on | What |
| --- | --- | --- |
| `forest.yml` | hq-dc01 | `microsoft.ad.domain`, then the SYSVOL gate and a wait for AD Web Services |
| `sites.yml` | hq-dc01 | Sites HQ/BRANCH (renames `Default-First-Site-Name`), subnets, site link, removes `DEFAULTIPSITELINK` |
| `replica.yml` | other DCs | DNS → forest root (only before promotion), `microsoft.ad.domain_controller` in its site, SYSVOL gate |
| `dns.yml` | every DC | Forwarder = own site firewall; zone scopes + reverse zones (root DC); resolver order partner → self |
| `time.yml` | PDC | NTP from the HQ firewall; everyone else follows the domain hierarchy |
| `ous.yml` | hq-dc01 | OU tree from `ad_ous` (`group_vars/domain_controllers.yml`), protected from deletion |
| `verify.yml` | every DC | Health gates: dcdiag, SYSVOL state Normal, `repadmin /replsummary` with 0 failures |

The playbook ends by writing `docs/ad/health-report.md`, and only gets there if every gate
passed. Two runs in a row report `changed=0` on both DCs.

## Pitfalls found while building it

Each of these is handled in the code, at the line that mentions it.

1. **DFSR start race after promotion.**
   - DFSR started before WMI was ready and logged event 6104, then 1202 every hour. SYSVOL was never
     initialized (`SysvolReady=0`), so Netlogon did not advertise the DC and the DC locator failed
     with 1355.
   - That made the domain look absent. `microsoft.ad.domain` then retried `Install-ADDSForest`,
     which failed with "DomainNetbiosName not recognized".
   - Fix: `sysvol.yml` waits for SYSVOL and advertisement, and restarts DFSR when it is stuck.
     Event 4602 and `SysvolReady=1` followed within seconds.
2. **Zones in the "Legacy" partition.**
   - The same promotion left the domain zone and `_msdcs` in the domain naming context rather
     than in the DNS application partitions.
   - Creating forest-scoped reverse zones then failed silently, because PowerShell's default
     error action is Continue.
   - Fix: `dns.yml` enforces each zone's replication scope with `ErrorActionPreference = 'Stop'`.
3. **Double hop over WinRM/NTLM.**
   - A network logon carries no reusable credentials, so a DC calling *another* DC's AD Web
     Services fails. Measured: `Get-ADReplicationSite -Server hq-dc01` from br-dc01 fails without
     `become` and works with it.
   - Fix: the DC plays use `become` (runas Administrator with password).
4. **IPv6 resolver flip-flop.**
   - `win_dns_client` with only IPv4 servers removed `::1`, which the DNS Server role re-adds, so
     the task reported a change on every run.
   - Fix: `::1` is part of the desired list.

`dcdiag` skips `SystemLog` and `DFSREvent`: they report event-log *history* (1 h / 24 h), so they
keep failing after the fact. SYSVOL health is checked as current state instead.
