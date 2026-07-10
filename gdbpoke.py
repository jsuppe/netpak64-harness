#!/usr/bin/env python3
"""gdbpoke.py — write bytes into a running ares over the GDB stub.
Usage: gdbpoke.py <port> <hexaddr> <hexbytes> [<hexaddr> <hexbytes> ...]
e.g.:  gdbpoke.py 9167 8041b9c9 02   (set gNetSpecView = FRONT)"""
import socket, sys

def csum(p): return sum(p.encode()) & 0xFF
port = int(sys.argv[1])
s = socket.create_connection(("::1", port), timeout=5)
def send(p): s.sendall(f"${p}#{csum(p):02x}".encode())
def recv_pkt(timeout=5.0):
    s.settimeout(timeout); buf = b""
    while True:
        c = s.recv(65536)
        if not c: return None
        buf += c
        i = buf.find(b"$")
        if i >= 0:
            j = buf.find(b"#", i)
            if j >= 0 and len(buf) >= j + 3:
                s.sendall(b"+"); return buf[i+1:j].decode()
s.sendall(b"+"); send("qSupported:swbreak+"); recv_pkt()
s.sendall(b"\x03"); recv_pkt()
args = sys.argv[2:]
for k in range(0, len(args), 2):
    addr, data = int(args[k], 16), args[k+1]
    send(f"M{addr:x},{len(data)//2:x}:{data}")
    r = recv_pkt()
    print(f"{addr:08x} <- {data}  ({r})")
send("c")
