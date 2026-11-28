"""Proxmox API helpers shared by the lab tests: guest-agent exec, VM power, readiness.

Talks to the host's own API over loopback with the Terraform token (~/.config/pve/...).
"""
import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://127.0.0.1:8006/api2/json/nodes/pve"
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
    r = api("POST", f"qemu/{vmid}/agent/exec", [("command", a) for a in argv])
    if not r.get("data"):
        raise RuntimeError(f"exec on {vmid} failed: {r.get('message')}")
    pid = r["data"]["pid"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = api("GET", f"qemu/{vmid}/agent/exec-status?pid={pid}").get("data") or {}
        if st.get("exited"):
            return st.get("exitcode", 0), st.get("out-data", "")
        time.sleep(0.5)
    raise RuntimeError(f"exec on {vmid} timed out: {argv}")


def wait_agent(name: str, vmid: int, timeout: float = 600) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if api("POST", f"qemu/{vmid}/agent/ping").get("data") is not None:
            return
        time.sleep(5)
    raise RuntimeError(f"{name}: guest agent never answered")


def wait_ready(name: str, vmid: int) -> None:
    """Guest agent answers and cloud-init has finished."""
    wait_agent(name, vmid)
    agent_exec(vmid, ["cloud-init", "status", "--wait"], timeout=600)


def wait_task(upid: str, timeout: float = 600) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = api("GET", f"tasks/{urllib.parse.quote(upid)}/status").get("data") or {}
        if st.get("status") == "stopped":
            if st.get("exitstatus") != "OK":
                raise RuntimeError(f"task {upid} ended with {st.get('exitstatus')}")
            return
        time.sleep(2)
    raise RuntimeError(f"task {upid} timed out")


def status(vmid: int) -> str:
    return (api("GET", f"qemu/{vmid}/status/current").get("data") or {}).get("status", "unknown")


def shutdown(vmid: int, timeout: int = 300) -> None:
    """Clean guest shutdown (ACPI / agent), like an admin taking a server down."""
    wait_task(api("POST", f"qemu/{vmid}/status/shutdown", [("timeout", str(timeout))])["data"], timeout + 60)


def start(vmid: int) -> None:
    if status(vmid) != "running":
        wait_task(api("POST", f"qemu/{vmid}/status/start", [])["data"])
