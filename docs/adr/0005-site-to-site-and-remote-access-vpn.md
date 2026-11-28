# ADR-0005: Site-to-site and remote-access VPN with WireGuard

- Status: Accepted
- Date: 2026-11-28

## Context

Branch users authenticate against both domain controllers, the DCs replicate across sites, and
admins must reach both sites from outside without exposing any management port to the WAN
(issue #6). Both firewalls run OPNsense 26.7, where WireGuard ships in core.

## Decision

1. **WireGuard rather than IPsec.**
   - The configuration is small and declarative (keys plus allowed IPs), easy to render from inventory.
   - It runs in the kernel on OPNsense, and every peer is one public key that can be reviewed.
2. **A routed site-to-site tunnel, not policy-based.**
   - `wg0` on each firewall uses a /30 transfer net, `172.31.255.0/30` (HQ `.1`, Branch `.2`).
   - AllowedIPs carry the other site's /16, and OPNsense installs those routes itself.
   - Traffic crossing the tunnel is filtered like any other interface, by explicit rules on the
     `wireguard` interface group (deny by default).
   - A pre-shared key is added on top of the key pair, as post-quantum hardening of the handshake.
3. **Remote access terminates at HQ only.**
   - `wg1` on `hq-fw01` listens on UDP 51821, the only port open to the whole WAN. The pool is `172.31.0.0/24`.
   - The Branch is reached *through* the site-to-site tunnel: Branch routes the pool back over
     `wg0`, so there is one VPN endpoint to harden and audit.
   - The tunnel is split: clients route only `172.16.0.0/16` and `172.17.0.0/16`, not their Internet traffic.
   - The pool reaches the Mgmt and Servers VLANs on management ports, plus the firewall GUI.
     It never reaches client VLANs or the DMZ.
4. **Keys are lab secrets, not code.**
   - `scripts/lab-secrets.sh` creates the missing keys in `~/.config/lab/secrets.json` (idempotent).
   - Ansible renders them into the firewall configs and into the client configs in
     `ansible/build/wireguard/`, which are never committed.
5. **Proof is automated.**
   - The firewall role fails unless every site-to-site peer has completed a handshake.
   - `tests/firewall/policy.yml` covers the cross-site flows, a TCP traceroute through the tunnel
     address, the WAN exposure before the VPN is up, and the remote-access permissions.

## Consequences

- Adding an admin means a new key name in `lab-secrets.sh`, a peer and a client entry in
  `host_vars/hq-fw01.yml`, then running the playbook. Revoking one means removing the peer.
- There is a single VPN endpoint, so remote access is down whenever `hq-fw01` is down. That is
  acceptable for a lab; a production design would add a CARP pair.
- The test peer `rw-test` stays configured permanently, but its key exists only on the test probe.
