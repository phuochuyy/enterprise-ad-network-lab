#!/usr/bin/env python3
"""Run the firewall policy test (tests/firewall/policy.yml) against probes that already exist.

Everything goes through the Proxmox guest-agent API - no route from the host into the lab
VLANs, no SSH, no extra firewall rule for the test itself. Writes a Markdown report.

Usage: run.py <policy.yml> <report.md>      (scripts/fw-policy-test.sh creates/destroys probes)
"""
import base64
import datetime
import json
import os
import subprocess
import sys
import time

import yaml  # PyYAML, from the ansible-core venv

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
from pve import agent_exec, api, wait_ready  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def install_probe(vmid: int) -> None:
    with open(os.path.join(HERE, "probe.py"), "rb") as fh:
        content = base64.b64encode(fh.read()).decode()
    r = api("POST", f"qemu/{vmid}/agent/file-write",
            [("file", "/usr/local/bin/fwprobe"), ("content", content), ("encode", "0")])
    if r.get("message"):
        raise RuntimeError(f"upload to {vmid} failed: {r['message']}")
    agent_exec(vmid, ["chmod", "0755", "/usr/local/bin/fwprobe"])


def verdict(expect: str, result: dict, dst_ip: str) -> bool:
    if expect.startswith("via "):
        hops = result.get("hops", [])
        return expect.split()[1] in hops and hops[-1:] == [dst_ip]
    if expect == "allow":
        return result["result"] in ("open", "reply")
    return result["result"] == "timeout"


def bring_up_vpn(name: str, p: dict) -> None:
    """Install wireguard-tools on the probe and bring its tunnel up (config rendered by Ansible)."""
    print(f"--- {name}: VPN up ({p['vpn']['config']})", flush=True)
    rc, out = agent_exec(p["vm_id"], ["sh", "-c", "DEBIAN_FRONTEND=noninteractive apt-get -qq update && "
                                      "DEBIAN_FRONTEND=noninteractive apt-get -qq -y install wireguard-tools"],
                         timeout=600)
    if rc != 0:
        raise SystemExit(f"{name}: installing wireguard-tools failed: {out[-500:]}")
    with open(os.path.join(REPO, p["vpn"]["config"]), "rb") as fh:
        content = base64.b64encode(fh.read()).decode()
    api("POST", f"qemu/{p['vm_id']}/agent/file-write",
        [("file", "/etc/wireguard/wg0.conf"), ("content", content), ("encode", "0")])
    rc, out = agent_exec(p["vm_id"], ["sh", "-c", "chmod 600 /etc/wireguard/wg0.conf && (wg-quick down wg0 >/dev/null 2>&1; wg-quick up wg0 2>&1)"])
    if rc != 0:
        raise SystemExit(f"{name}: wg-quick up failed: {out[-500:]}")


def main(policy_file: str, report_file: str) -> int:
    with open(policy_file) as fh:
        policy = yaml.safe_load(fh)
    probes = policy["probes"]

    for name, p in probes.items():
        print(f"--- preparing {name} ({p['name']}, VLAN {p.get('vlan', 'untagged')}, {p['ip']})", flush=True)
        wait_ready(name, p["vm_id"])
        install_probe(p["vm_id"])
        # Re-runs against kept probes (KEEP=1): stop listeners of an earlier run first.
        # pkill is exec'd directly (no shell), and pkill never signals itself.
        agent_exec(p["vm_id"], ["pkill", "-f", "/usr/local/bin/fwprobe listen"])
        lst = policy.get("listen", {}).get(name, {})
        argv = ["/usr/local/bin/fwprobe", "listen", "--bind", p["ip"],
                "--tcp", ",".join(map(str, lst.get("tcp", []))),
                "--udp", ",".join(map(str, lst.get("udp", [])))]
        _, out = agent_exec(p["vm_id"], argv)
        served = json.loads(out)
        print(f"    listening: {' '.join(served['listening'])}", flush=True)
        # A target port without a listener would turn an allowed flow into a false "refused".
        if served["unserved"]:
            raise SystemExit(f"{name}: no listener on {served['unserved']} - fix the probe, not the firewall")

    rows: dict[int, tuple] = {}
    started = time.time()
    cases = list(enumerate(policy["cases"]))
    # Cases marked pre-vpn run before any probe brings its tunnel up; then the tunnels; then the rest.
    ordered = [c for c in cases if c[1].get("stage") == "pre-vpn"] + [None] + \
              [c for c in cases if c[1].get("stage") != "pre-vpn"]
    for item in ordered:
        if item is None:
            for name, p in probes.items():
                if "vpn" in p:
                    bring_up_vpn(name, p)
            continue
        idx, c = item
        src = probes[c["from"]]
        if c["to"] == "fw":
            dst_ip, dst_label = src["gateway"], f"firewall ({src['gateway']})"
        elif c["to"] in probes:
            dst_ip, dst_label = probes[c["to"]]["ip"], f"{c['to']} ({probes[c['to']]['ip']})"
        elif c["to"] in policy.get("targets", {}):
            dst_ip = policy["targets"][c["to"]]
            dst_label = f"{c['to']} ({dst_ip})"
        else:
            dst_ip, dst_label = c["to"], c["to"]
        if c["proto"] == "path":
            argv = ["/usr/local/bin/fwprobe", "path", dst_ip, str(c["port"])]
        else:
            argv = ["/usr/local/bin/fwprobe", "check", c["proto"], dst_ip]
            if c["proto"] != "icmp":
                argv.append(str(c["port"]))
        _, out = agent_exec(src["vm_id"], argv)
        result = json.loads(out)
        ok = verdict(c["expect"], result, dst_ip)
        got = " > ".join(result["hops"]) if c["proto"] == "path" else result["result"]
        svc = ("TCP" if c["proto"] == "path" else c["proto"].upper()) + \
            (f"/{c['port']}" if c["proto"] != "icmp" else "") + (" path" if c["proto"] == "path" else "")
        rows[idx] = (ok, c["from"], dst_label, svc, c["expect"], got, c["why"])
        print(f"    [{'PASS' if ok else 'FAIL'}] {c['from']:8} -> {dst_label:28} {svc:14} "
              f"expect {c['expect']:18} got {got:10} {c['why']}", flush=True)
    rows = [rows[i] for i in sorted(rows)]
    failures = sum(1 for r in rows if not r[0])

    elapsed = time.time() - started
    commit = subprocess.run(["git", "-C", HERE, "rev-parse", "--short", "HEAD"],
                            capture_output=True, text=True).stdout.strip()
    if subprocess.run(["git", "-C", HERE, "status", "--porcelain", "--untracked-files=no"],
                      capture_output=True, text=True).stdout.strip():
        commit += " (dirty - uncommitted changes)"
    with open(report_file, "w") as fh:
        fh.write("# Firewall policy test report\n\n")
        fh.write("Generated by `scripts/fw-policy-test.sh` from `tests/firewall/policy.yml`. Traffic is "
                 "real: one probe VM per VLAN, commands run through the Proxmox guest agent.\n\n")
        fh.write(f"- Run: {datetime.datetime.now().astimezone():%Y-%m-%d %H:%M %Z} - commit `{commit}`\n")
        fh.write(f"- Result: **{len(rows) - failures}/{len(rows)} passed** in {elapsed:.0f} s\n")
        fh.write("- `allow` = connection / reply; `deny` = timeout (pf drops); every target port has a listener; "
                 "`via` = a TCP traceroute to the port passes that hop\n\n")
        fh.write("| | From | To | Service | Expect | Got | Why |\n| --- | --- | --- | --- | --- | --- | --- |\n")
        for ok, frm, to, svc, exp, res, why in rows:
            fh.write(f"| {'✅' if ok else '❌'} | {frm} | {to} | {svc} | {exp} | {res} | {why} |\n")
    print(f"--- {len(rows) - failures}/{len(rows)} passed in {elapsed:.0f}s - report: {report_file}")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
