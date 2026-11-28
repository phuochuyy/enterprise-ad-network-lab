# Role `dhcp`

A Windows DHCP failover pair on the domain controllers (issue #8), driven by `playbooks/dhcp.yml`.
Data lives in `group_vars/domain_controllers.yml` (`dhcp_scopes`, `dhcp_failover`).

- **Role and AD setup**: the DHCP role is installed on both DCs, authorized in AD, and the
  DHCP security groups are created.
- **Scopes**: the HQ and Branch Users scopes are defined on `dhcp_primary`, with router, DNS
  (own site's DC first) and domain options.
- **Failover**: one load-balance relationship (50/50) covers both scopes, so either DC serves
  either site. Scope changes are pushed to the partner with `Invoke-DhcpServerv4FailoverReplication`.
- **Health gate**: the relationship must be Normal on both DCs, and every scope must be active on each.
- **Relay**: clients reach the DCs through `dhcrelay` on both firewalls (`opnsense_dhcp_relays`),
  towards *both* DCs. The remote one is reached over the WireGuard tunnel.

Proof: `scripts/dhcp-failover-test.sh` → `docs/dhcp/failover-test-report.md`. Each DC is shut
down in turn, and clients at both sites still get a correct lease from the survivor.

## Pitfalls found while building it

1. **Windows PowerShell 5.1 and `ConvertFrom-Json`.**
   - A JSON array comes back as ONE object, so `@(... | ConvertFrom-Json)` nests it. The first
     run passed a nested array to `-ScopeId`, and the failover creation failed.
   - It was briefly mistaken for a timing issue.
   - Fix: unroll with `ForEach-Object { $_ }`.
2. **MCLT 1 h meant waiting 1 h after every outage.**
   - A server that comes back after its partner went PARTNER DOWN stays in RECOVER WAIT for the
     whole MCLT before the pair is Normal again.
   - Lab values: MCLT 5 min, automatic switch to PARTNER DOWN after 2 min. Production keeps
     MCLT 1 h.
   - The role enforces both values on an existing relationship, not only at creation.
3. **Cross-site relay rule.**
   - `dhcrelay` forwards from the relay address (giaddr, e.g. `172.16.30.1`). With `hq-dc01`
     down, br-fw01 dropped those packets on `wg0`, as the filter log showed.
   - Fix: a rule per site for UDP 67 from the other site to its DC. The inter-VLAN policy test
     had no DHCP case; only the end-to-end failover test found it.
4. **Observed behaviour, not a bug:** in COMMUNICATION INTERRUPTED the surviving server answered
   *every* client within a second, not only the half of the hash range it normally owns.
