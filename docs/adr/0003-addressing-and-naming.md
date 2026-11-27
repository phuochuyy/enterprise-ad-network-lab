# ADR-0003: Addressing, naming and AD domain name

- Status: Accepted
- Date: 2026-11-27

## Context

Addresses and names are expensive to change once AD, DHCP, firewall rules and monitoring depend on
them. The lab must also coexist with the host network (192.168.0.0/24 home LAN, 10.10.10.0/24 NAT).

## Decision

1. **Per-site /16 supernets** — HQ `172.16.0.0/16`, Branch `172.17.0.0/16`, VPN `172.31.0.0/16`.
   One summary route per site; no overlap with common home ranges (192.168.x, 10.x).
2. **Third octet = function** at both sites (`.20` servers, `.30` users), VLAN IDs `x0` at HQ and
   `1x0` at Branch, so VLAN IDs stay unique if both sites are ever trunked together.
3. **AD forest `corp.huylab.internal`** (NetBIOS `CORP`). `.internal` is reserved by ICANN (2024)
   for private use, so it can never collide with a public delegation — unlike `.local` (mDNS conflicts)
   or `.lab` (not reserved). A dedicated sub-domain keeps the root free for other internal zones.
4. **Hostnames `<site>-<role><nn>`**, VMID ranges by function — see `docs/architecture.md`.

## Consequences

- Firewall aliases, DHCP scopes and monitoring discovery can be written per supernet.
- Public certificates cannot be issued for `.internal`; an internal CA (AD CS) is needed if TLS is added.
- Renumbering later would require AD site/subnet, DHCP and firewall changes — avoided by deciding now.
