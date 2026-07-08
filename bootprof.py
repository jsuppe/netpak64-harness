#!/usr/bin/env python3
"""bootprof.py — sample the PC of a booting ROM via the ares GDB stub.
Connects to ::1:<port>, then loops: interrupt (0x03) -> read PC from the
g-packet (64-bit regs, PC at index 37) -> continue. Prints one PC per sample.
Usage: bootprof.py <port> <samples> <interval_s>
"""
import socket
import sys
import time

port, n, iv = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])

def csum(p):
    return sum(p.encode()) & 0xFF

def send(s, p):
    s.sendall(f"${p}#{csum(p):02x}".encode())

def recv_pkt(s, timeout=3.0):
    s.settimeout(timeout)
    buf = b""
    try:
        while True:
            c = s.recv(4096)
            if not c:
                break
            buf += c
            i = buf.find(b"$")
            if i >= 0:
                j = buf.find(b"#", i)
                if j >= 0 and len(buf) >= j + 3:
                    s.sendall(b"+")
                    return buf[i + 1:j].decode()
    except socket.timeout:
        pass
    return None

s = socket.create_connection(("::1", port), timeout=5)
s.sendall(b"+")
send(s, "qSupported:swbreak+")
recv_pkt(s)
for k in range(n):
    time.sleep(iv)
    s.sendall(b"\x03")          # interrupt -> stop reply
    recv_pkt(s)
    send(s, "g")
    g = recv_pkt(s)
    if g and len(g) >= 38 * 16:
        pc = g[37 * 16:38 * 16]
        print(f"{k*iv+iv:5.1f}s PC=0x{pc[-8:]}")
    else:
        print(f"{k*iv+iv:5.1f}s PC=?")
    send(s, "c")
s.close()
