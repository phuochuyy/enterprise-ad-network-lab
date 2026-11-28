#!/usr/bin/env python3
"""DHCP failover test (tests/dhcp/failover.yml) against clients that already exist.

Clients are driven through the Proxmox guest agent; DCs are powered through the Proxmox API and
queried over WinRM (HTTPS, NTLM - the host routes into the sites, scripts/host/lab-routes).
For each scenario a DC is shut down cleanly, every client throws its lease away and runs a
fresh DHCP exchange (DISCOVER through the firewall relay), and the survivor must answer with
the right address, router, DNS servers and domain. The DC is then started again and the
failover relationship must return to Normal. Writes a Markdown report.

Usage: run.py <failover.yml> <report.md>      (scripts/dhcp-failover-test.sh creates/destroys clients)
"""
import datetime
import ipaddress
import json
import os
import subprocess
import sys
import time

import winrm  # pywinrm, from the ansible-core venv
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import pve  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SECRETS = os.path.expanduser("~/.config/lab/secrets.json")

# Throw the lease away, then let systemd-networkd start over from INIT (broadcast DISCOVER).
RENEW = ('IF=$(ls /sys/class/net | grep -v ^lo | head -1); ip -4 addr flush dev "$IF"; '
         'rm -f /run/systemd/netif/leases/*; networkctl reconfigure "$IF"')
LEASE = 'cat /run/systemd/netif/leases/* 2>/dev/null'


def winrm_ps(ip: str, script: str) -> str:
    with open(SECRETS) as fh:
        pw = json.load(fh)["admin_password"]
    s = winrm.Session(f"https://{ip}:5986/wsman", auth=("Administrator", pw),
                      transport="ntlm", server_cert_validation="ignore")
    r = s.run_ps(script)
    if r.status_code != 0:
        raise RuntimeError(f"{ip}: {r.std_err.decode(errors='replace')[-400:]}")
    return r.std_out.decode(errors="replace").strip()


def failover_state(dc_ip: str, name: str) -> str:
    try:
        return winrm_ps(dc_ip, f"(Get-DhcpServerv4Failover -Name '{name}').State")
    except Exception as exc:  # DC still booting
        return f"unreachable ({type(exc).__name__})"


def wait_failover_normal(test: dict, timeout: float = 900) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        states = {dc: failover_state(d["ip"], test["failover_name"]) for dc, d in test["dcs"].items()}
        if all(s == "Normal" for s in states.values()):
            return ", ".join(f"{k} {v}" for k, v in states.items())
        time.sleep(20)
    raise RuntimeError(f"failover did not return to Normal: {states}")


def lease(vmid: int) -> dict:
    _, out = pve.agent_exec(vmid, ["sh", "-c", LEASE])
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def fresh_lease(name: str, vmid: int, timeout: float = 480) -> tuple[dict, float]:
    """Discard the lease, run DHCP from scratch, wait for a new one. Returns (lease, seconds)."""
    started = time.time()
    pve.agent_exec(vmid, ["sh", "-c", RENEW])
    while time.time() - started < timeout:
        current = lease(vmid)
        if current.get("ADDRESS") and current.get("SERVER_ADDRESS"):
            return current, time.time() - started
        time.sleep(3)
    raise RuntimeError(f"{name}: no lease within {timeout:.0f}s")


def check_lease(client: str, got: dict, test: dict, want_server: str | None) -> list[tuple[str, bool, str]]:
    exp = test["expect"][client]
    lo, hi = (ipaddress.ip_address(a) for a in exp["range"])
    addr = got.get("ADDRESS", "")
    dns = got.get("DNS", "").split()
    checks = [
        ("address in scope range", bool(addr) and lo <= ipaddress.ip_address(addr) <= hi, addr),
        ("router", got.get("ROUTER") == exp["router"], got.get("ROUTER", "")),
        ("DNS servers (own site DC first)", dns == exp["dns"], " ".join(dns)),
        ("domain", got.get("DOMAINNAME") == test["domain"], got.get("DOMAINNAME", "")),
    ]
    if want_server:
        checks.append(("answered by", got.get("SERVER_ADDRESS") == want_server, got.get("SERVER_ADDRESS", "")))
    return checks


def main(test_file: str, report_file: str) -> int:
    with open(test_file) as fh:
        test = yaml.safe_load(fh)
    clients, dcs = test["clients"], test["dcs"]
    sections, failures = [], 0
    started = time.time()

    def record(title: str, rows: list[tuple[str, str, bool, str]]) -> None:
        nonlocal failures
        print(f"--- {title}", flush=True)
        for who, check, ok, value in rows:
            failures += not ok
            print(f"    [{'PASS' if ok else 'FAIL'}] {who:6} {check}: {value}", flush=True)
        sections.append((title, rows))

    for name, c in clients.items():
        print(f"--- preparing {name} ({c['name']}, VLAN {c['vlan']})", flush=True)
        pve.wait_ready(name, c["vm_id"])

    # Baseline: both DCs up. Leases must exist on BOTH DCs (failover replicates them).
    print(f"--- failover state: {wait_failover_normal(test)}", flush=True)
    rows = []
    for name, c in clients.items():
        got, secs = fresh_lease(name, c["vm_id"])
        rows += [(name, chk, ok, val) for chk, ok, val in check_lease(name, got, test, None)]
        for dc, d in dcs.items():
            known = winrm_ps(d["ip"], f"[bool](Get-DhcpServerv4Lease -IPAddress {got['ADDRESS']} -ErrorAction SilentlyContinue)")
            rows.append((name, f"lease replicated to {dc}", known == "True", got["ADDRESS"]))
        rows.append((name, "lease time", True, f"{secs:.0f}s from {got.get('SERVER_ADDRESS')}"))
    record("Baseline - both DCs up", rows)

    for sc in test["scenarios"]:
        down, survivor = dcs[sc["down"]], dcs[sc["survivor"]]
        print(f"--- shutting down {sc['down']}", flush=True)
        pve.shutdown(down["vm_id"])
        rows = []
        for name, c in clients.items():
            got, secs = fresh_lease(name, c["vm_id"])
            rows += [(name, chk, ok, val) for chk, ok, val in check_lease(name, got, test, survivor["ip"])]
            rows.append((name, "lease time", True, f"{secs:.0f}s"))
        rows.append(("-", f"{sc['survivor']} failover state while partner down", True,
                     failover_state(survivor["ip"], test["failover_name"])))
        print(f"--- starting {sc['down']} again", flush=True)
        pve.start(down["vm_id"])
        rows.append(("-", "failover back to Normal", True, wait_failover_normal(test)))
        record(f"{sc['down']} down - {sc['survivor']} must serve both sites", rows)

    elapsed = time.time() - started
    total = sum(len(r) for _, r in sections)
    commit = subprocess.run(["git", "-C", HERE, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    if subprocess.run(["git", "-C", HERE, "status", "--porcelain", "--untracked-files=no"],
                      capture_output=True, text=True).stdout.strip():
        commit += " (dirty - uncommitted changes)"
    with open(report_file, "w") as fh:
        fh.write("# DHCP failover test report\n\n")
        fh.write("Generated by `scripts/dhcp-failover-test.sh` from `tests/dhcp/failover.yml`. Real DHCP clients "
                 "in each site's Users VLAN; each domain controller is shut down in turn and every client "
                 "discards its lease and runs a fresh DHCP exchange through the firewall relay.\n\n")
        fh.write(f"- Run: {datetime.datetime.now().astimezone():%Y-%m-%d %H:%M %Z} - commit `{commit}`\n")
        fh.write(f"- Result: **{total - failures}/{total} checks passed** in {elapsed / 60:.0f} min\n")
        for title, rows in sections:
            fh.write(f"\n## {title}\n\n| | Client | Check | Value |\n| --- | --- | --- | --- |\n")
            for who, check, ok, value in rows:
                fh.write(f"| {'✅' if ok else '❌'} | {who} | {check} | {value} |\n")
    print(f"--- {total - failures}/{total} passed in {elapsed / 60:.0f} min - report: {report_file}")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
