#!/usr/bin/env python3
"""File share access test (tests/fileserver/access.yml) against clients that already exist.

Real domain users connect with smbclient to the DFS namespace from Linux clients in the Users
VLANs (commands run through the Proxmox guest agent). Checks per user: which namespace folders
access-based enumeration shows, and per case whether a read or write is allowed or denied.
A denial must be an explicit SMB answer (ACCESS_DENIED, or the folder hidden by ABE);
logon, network or timeout errors are test errors, never a passing "deny". Writes a report.

Usage: run.py <access.yml> <report.md>      (scripts/fs-access-test.sh creates/destroys clients)
"""
import base64
import datetime
import json
import os
import re
import subprocess
import sys
import time

import yaml

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import pve  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SECRETS = os.path.expanduser("~/.config/lab/secrets.json")
DENIED = ("NT_STATUS_ACCESS_DENIED", "NT_STATUS_OBJECT_NAME_NOT_FOUND", "NT_STATUS_OBJECT_PATH_NOT_FOUND",
          "NT_STATUS_BAD_NETWORK_NAME")
INFRA = ("LOGON_FAILURE", "CONNECTION", "TIMEOUT", "NETWORK_UNREACHABLE", "HOST_UNREACHABLE", "IO_TIMEOUT")


def install_smbclient(name: str, vmid: int) -> None:
    for attempt in range(3):
        rc, out = pve.agent_exec(vmid, ["sh", "-c", "DEBIAN_FRONTEND=noninteractive apt-get -qq update && "
                                        "DEBIAN_FRONTEND=noninteractive apt-get -qq -y install smbclient 2>&1"],
                                 timeout=600)
        if rc == 0:
            return
        time.sleep(15)
    raise SystemExit(f"{name}: installing smbclient failed: {out[-400:]}")


def write_credentials(vmid: int, user: str, domain: str, password: str) -> str:
    path = f"/root/smb-{user}.cred"
    content = f"username={user}\npassword={password}\ndomain={domain}\n"
    pve.api("POST", f"qemu/{vmid}/agent/file-write",
            [("file", path), ("content", base64.b64encode(content.encode()).decode()), ("encode", "0")])
    pve.agent_exec(vmid, ["chmod", "600", path])
    return path


def smb(vmid: int, namespace: str, cred: str, command: str) -> str:
    _, out = pve.agent_exec(vmid, ["sh", "-c", f"smbclient '{namespace}' -A '{cred}' -m SMB3 -c '{command}' 2>&1"],
                            timeout=120)
    return out


def classify(out: str) -> str:
    """allowed | denied:<status> | error:<status>"""
    status = re.findall(r"NT_STATUS_[A-Z_]+", out)
    if not status:
        return "allowed"
    if any(any(k in s for k in INFRA) for s in status):
        return f"error:{status[0]}"
    if any(s in DENIED for s in status):
        return f"denied:{next(s for s in status if s in DENIED)}"
    return f"error:{status[0]}"


def main(test_file: str, report_file: str) -> int:
    with open(test_file) as fh:
        test = yaml.safe_load(fh)
    with open(SECRETS) as fh:
        password = json.load(fh)["ad_test_user_password"]
    clients, ns = test["clients"], test["namespace"]
    started = time.time()

    for name, c in test["clients"].items():
        print(f"--- preparing {name} ({c['name']}, VLAN {c['vlan']})", flush=True)
        pve.wait_ready(name, c["vm_id"])
        install_smbclient(name, c["vm_id"])

    creds = {}
    for user, u in test["users"].items():
        creds[user] = write_credentials(clients[u["from"]]["vm_id"], user, test["domain"], password)

    rows, failures = [], 0

    def record(ok: bool, *cells: str) -> None:
        nonlocal failures
        failures += not ok
        rows.append((ok, *cells))
        print(f"    [{'PASS' if ok else 'FAIL'}] " + " | ".join(cells), flush=True)

    print("--- what each user sees in the namespace (access-based enumeration)", flush=True)
    for user, u in test["users"].items():
        out = smb(clients[u["from"]]["vm_id"], ns, creds[user], "ls")
        # DFS links list as "Dr" (directory + reparse point), so the attribute letters are mixed case.
        seen = sorted(m.group(1) for m in re.finditer(r"^\s+(\S+)\s+D[A-Za-z]*\s+0\s", out, re.M)
                      if m.group(1) not in (".", ".."))
        record(seen == sorted(u["visible"]) and classify(out) == "allowed",
               user, u["from"], "list namespace", f"sees {', '.join(seen) or '(nothing)'}",
               f"expect {', '.join(sorted(u['visible']))}")

    print("--- read / write", flush=True)
    for c in test["cases"]:
        u = test["users"][c["user"]]
        vmid = clients[u["from"]]["vm_id"]
        if c["op"] == "read":
            command = f"cd {c['folder']}; ls"
        else:
            probe = f"access-test-{c['user']}.txt"
            command = f"cd {c['folder']}; put /etc/hostname {probe}; rm {probe}"
        result = classify(smb(vmid, ns, creds[c["user"]], command))
        ok = (result == "allowed") if c["expect"] == "allow" else result.startswith("denied:")
        record(ok, c["user"], u["from"], f"{c['op']} {c['folder']}", f"expect {c['expect']}", f"got {result}", c["why"])

    elapsed = time.time() - started
    commit = subprocess.run(["git", "-C", HERE, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    if subprocess.run(["git", "-C", HERE, "status", "--porcelain", "--untracked-files=no"],
                      capture_output=True, text=True).stdout.strip():
        commit += " (dirty - uncommitted changes)"
    with open(report_file, "w") as fh:
        fh.write("# File share access test report\n\n")
        fh.write("Generated by `scripts/fs-access-test.sh` from `tests/fileserver/access.yml`: real domain users, "
                 f"real SMB 3 through the DFS namespace `{ns}`, from Linux clients in the HQ and Branch Users "
                 "VLANs. A deny must be an explicit SMB answer (access denied, or the folder hidden by "
                 "access-based enumeration).\n\n")
        fh.write(f"- Run: {datetime.datetime.now().astimezone():%Y-%m-%d %H:%M %Z} - commit `{commit}`\n")
        fh.write(f"- Result: **{len(rows) - failures}/{len(rows)} passed** in {elapsed:.0f} s\n\n")
        fh.write("| | User | From | Check | Result | Expected / why |\n| --- | --- | --- | --- | --- | --- |\n")
        for ok, *cells in rows:
            fh.write(f"| {'✅' if ok else '❌'} | {cells[0]} | {cells[1]} | {cells[2]} | {cells[3]} | "
                     f"{' - '.join(cells[4:])} |\n")
    print(f"--- {len(rows) - failures}/{len(rows)} passed in {elapsed:.0f}s - report: {report_file}")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
