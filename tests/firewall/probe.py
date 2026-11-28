#!/usr/bin/env python3
"""Probe helper for the firewall policy test. Runs ON the probe VMs (stdlib only).

  probe.py listen --bind <ip> --tcp 22,445 --udp 53   serve the ports in the background
  probe.py check tcp|udp|icmp <ip> [port]   print one JSON line: {"result": ...}
  probe.py path <ip> <port>                 TCP traceroute: {"result": "path", "hops": [...]}

Results: open (TCP connect), reply (UDP or ICMP answer), timeout (nothing came back: what a pf
drop looks like), refused (the host answered with a reset / port unreachable), error:<text>.
The UDP check sends a real DNS query, so DNS servers and the echo listener both answer it.
"""
import argparse
import errno
import json
import os
import select
import socket
import struct
import subprocess
import sys
import time

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


def path(ip: str, port: int, max_hops: int = 6) -> list[str]:
    """TCP traceroute: SYNs to an allowed port with growing TTL, routers answer ICMP time exceeded.

    A UDP/ICMP traceroute would be dropped by pf at the first hop; a TCP SYN to a port the policy
    allows is forwarded hop by hop like the real traffic. Needs root (raw ICMP socket).
    """
    icmp = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
    hops = []
    for ttl in range(1, max_hops + 1):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_IP, socket.IP_TTL, ttl)
        s.setblocking(False)
        s.connect_ex((ip, port))
        hop, deadline = "*", time.time() + 2.5
        while hop == "*" and (left := deadline - time.time()) > 0:
            readable, writable, _ = select.select([icmp], [s], [], left)
            if writable and s.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR) in (0, errno.ECONNREFUSED):
                hop = ip  # SYN-ACK (or RST) from the destination itself
            elif readable:
                pkt, (src, _) = icmp.recvfrom(1500)
                ihl = (pkt[0] & 0x0F) * 4
                inner = pkt[ihl + 8:]
                # type 11 = time exceeded, for OUR probe (inner IP header's destination)
                if pkt[ihl] == 11 and len(inner) >= 20 and socket.inet_ntoa(inner[16:20]) == ip:
                    hop = src
        s.close()
        hops.append(hop)
        if hop == ip:
            break
    icmp.close()
    return hops


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
    pp = sub.add_parser("path")
    pp.add_argument("ip")
    pp.add_argument("port", type=int)
    args = ap.parse_args()
    if args.cmd == "listen":
        listen(args.bind, args.tcp, args.udp)
    elif args.cmd == "path":
        print(json.dumps({"result": "path", "hops": path(args.ip, args.port)}))
    else:
        print(json.dumps({"result": check(args.proto, args.ip, args.port)}))


if __name__ == "__main__":
    main()
