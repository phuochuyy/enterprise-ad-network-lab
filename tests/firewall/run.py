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
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import yaml  # PyYAML, from the ansible-core venv

API = "https://127.0.0.1:8006/api2/json/nodes/pve/qemu"
HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.expanduser(os.environ.get("TOKEN_FILE", "~/.config/pve/terraform-token.json"))
CTX = ssl._create_unverified_context()  # loopback to the host's self-signed API certificate


def api(method: str, path: str, data: list[tuple[str, str]] | None = None) -> dict:
    with open(TOKEN_FILE) as fh:
        tok = json.load(fh)
    req = urllib.request.Request(
        f"{API}/{path}",
        method=method,
        data=urllib.parse.urlencode(data).encode() if data is not None else None,
        headers={"Authorization": f"PVEAPIToken={tok['full-tokenid']}={tok['value']}"},
    )
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        return {"data": None, "message": exc.read().decode(errors="replace")}


def agent_exec(vmid: int, argv: list[str], timeout: float = 60) -> tuple[int, str]:
    r = api("POST", f"{vmid}/agent/exec", [("command", a) for a in argv])
    if not r.get("data"):
        raise RuntimeError(f"exec on {vmid} failed: {r.get('message')}")
    pid = r["data"]["pid"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = api("GET", f"{vmid}/agent/exec-status?pid={pid}").get("data") or {}
        if st.get("exited"):
            return st.get("exitcode", 0), st.get("out-data", "")
        time.sleep(0.5)
    raise RuntimeError(f"exec on {vmid} timed out: {argv}")


def wait_ready(name: str, vmid: int) -> None:
    deadline = time.time() + 600
    while time.time() < deadline:
        if api("POST", f"{vmid}/agent/ping").get("data") is not None:
            break
        time.sleep(5)
    else:
        raise RuntimeError(f"{name}: guest agent never answered")
    agent_exec(vmid, ["cloud-init", "status", "--wait"], timeout=600)


def install_probe(vmid: int) -> None:
    with open(os.path.join(HERE, "probe.py"), "rb") as fh:
        content = base64.b64encode(fh.read()).decode()
    r = api("POST", f"{vmid}/agent/file-write",
            [("file", "/usr/local/bin/fwprobe"), ("content", content), ("encode", "0")])
    if r.get("message"):
        raise RuntimeError(f"upload to {vmid} failed: {r['message']}")
    agent_exec(vmid, ["chmod", "0755", "/usr/local/bin/fwprobe"])


def verdict(expect: str, result: str) -> bool:
    passed = result in ("open", "reply")
    return passed if expect == "allow" else result == "timeout"


def main(policy_file: str, report_file: str) -> int:
    with open(policy_file) as fh:
        policy = yaml.safe_load(fh)
    probes = policy["probes"]

    for name, p in probes.items():
        print(f"--- preparing {name} ({p['name']}, VLAN {p['vlan']}, {p['ip']})", flush=True)
        wait_ready(name, p["vm_id"])
        install_probe(p["vm_id"])
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

    rows, failures = [], 0
    started = time.time()
    for c in policy["cases"]:
        src = probes[c["from"]]
        if c["to"] == "fw":
            dst_ip, dst_label = src["gateway"], f"firewall ({src['gateway']})"
        elif c["to"] in probes:
            dst_ip, dst_label = probes[c["to"]]["ip"], f"{c['to']} ({probes[c['to']]['ip']})"
        else:
            dst_ip, dst_label = c["to"], c["to"]
        argv = ["/usr/local/bin/fwprobe", "check", c["proto"], dst_ip]
        if c["proto"] != "icmp":
            argv.append(str(c["port"]))
        _, out = agent_exec(src["vm_id"], argv)
        result = json.loads(out)["result"]
        ok = verdict(c["expect"], result)
        failures += not ok
        svc = c["proto"].upper() + (f"/{c['port']}" if c["proto"] != "icmp" else "")
        rows.append((ok, c["from"], dst_label, svc, c["expect"], result, c["why"]))
        print(f"    [{'PASS' if ok else 'FAIL'}] {c['from']:8} -> {dst_label:28} {svc:9} "
              f"expect {c['expect']:5} got {result:8} {c['why']}", flush=True)

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
        fh.write("- `allow` = connection / reply; `deny` = timeout (pf drops); every target port has a listener\n\n")
        fh.write("| | From | To | Service | Expect | Got | Why |\n| --- | --- | --- | --- | --- | --- | --- |\n")
        for ok, frm, to, svc, exp, res, why in rows:
            fh.write(f"| {'✅' if ok else '❌'} | {frm} | {to} | {svc} | {exp} | {res} | {why} |\n")
    print(f"--- {len(rows) - failures}/{len(rows)} passed in {elapsed:.0f}s - report: {report_file}")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
