#!/usr/bin/env python3
"""Probe helper for the firewall policy test. Runs ON the probe VMs (stdlib only).

  probe.py listen --bind <ip> --tcp 22,445 --udp 53   serve the ports in the background
  probe.py check tcp|udp|icmp <ip> [port]   print one JSON line: {"result": ...}

Results: open (TCP connect), reply (UDP or ICMP answer), timeout (nothing came back: what a pf
drop looks like), refused (the host answered with a reset / port unreachable), error:<text>.
The UDP check sends a real DNS query, so DNS servers and the echo listener both answer it.
"""
import argparse
import json
import os
import select
import socket
import struct
import subprocess
import sys

TIMEOUT = 3.0
DNS_QUERY = bytes.fromhex("f1ce01000001000000000000") + b"\x00" + struct.pack(">HH", 2, 1)  # ". IN NS"


def listen(bind: str, tcp: list[int], udp: list[int]) -> None:
    # Bind to the probe's own address, not 0.0.0.0: systemd-resolved holds 127.0.0.53:53.
    socks, unserved = [], []
    for port in tcp:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((bind, port))
            s.listen(16)
            socks.append(s)
        except OSError:
            s.close()
            # Fine if a real daemon already answers there (sshd on 22); otherwise report it.
            if check("tcp", bind, port) != "open":
                unserved.append(f"tcp/{port}")
    for port in udp:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.bind((bind, port))
            socks.append(s)
        except OSError:
            s.close()
            unserved.append(f"udp/{port}")
    print(json.dumps({"listening": [f"{'tcp' if s.type == socket.SOCK_STREAM else 'udp'}/{s.getsockname()[1]}"
                                    for s in socks], "unserved": unserved}))
    sys.stdout.flush()
    # Double fork: the guest agent waits for the process it started, not for the server.
    if os.fork():
        return
    os.setsid()
    if os.fork():
        os._exit(0)
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    while True:
        ready, _, _ = select.select(socks, [], [])
        for s in ready:
            if s.type == socket.SOCK_STREAM:
                conn, _ = s.accept()
                conn.close()
            else:
                data, peer = s.recvfrom(2048)
                s.sendto(data, peer)


def check(proto: str, ip: str, port: int | None) -> str:
    if proto == "icmp":
        rc = subprocess.run(["ping", "-c", "2", "-W", "2", ip], capture_output=True).returncode
        return "reply" if rc == 0 else "timeout"
    if proto == "tcp":
        try:
            socket.create_connection((ip, port), timeout=TIMEOUT).close()
            return "open"
        except ConnectionRefusedError:
            return "refused"
        except (TimeoutError, socket.timeout):
            return "timeout"
        except OSError as exc:
            return f"error:{exc.strerror or exc}"
    if proto == "udp":
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(TIMEOUT)
        try:
            s.connect((ip, port))  # connected UDP socket: ICMP port unreachable -> refused
            s.send(DNS_QUERY)
            s.recv(4096)
            return "reply"
        except ConnectionRefusedError:
            return "refused"
        except (TimeoutError, socket.timeout):
            return "timeout"
        except OSError as exc:
            return f"error:{exc.strerror or exc}"
        finally:
            s.close()
    raise SystemExit(f"unknown protocol {proto}")


def ports(text: str) -> list[int]:
    return [int(p) for p in text.split(",") if p]


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    lp = sub.add_parser("listen")
    lp.add_argument("--bind", required=True)
    lp.add_argument("--tcp", type=ports, default=[])
    lp.add_argument("--udp", type=ports, default=[])
    cp = sub.add_parser("check")
    cp.add_argument("proto", choices=["tcp", "udp", "icmp"])
    cp.add_argument("ip")
    cp.add_argument("port", type=int, nargs="?")
    args = ap.parse_args()
    if args.cmd == "listen":
        listen(args.bind, args.tcp, args.udp)
    else:
        print(json.dumps({"result": check(args.proto, args.ip, args.port)}))


if __name__ == "__main__":
    main()
