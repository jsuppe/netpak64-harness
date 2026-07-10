#!/usr/bin/env python3
"""perfdump.py — read the in-ROM perf accumulator (0x8052F800) over the ares
GDB stub and print per-frame averages. us = cycles * 64 / 3000.
Usage: perfdump.py <port>"""
import socket, struct, sys

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
def read_mem(addr, n):
    out = b""
    while n > 0:
        k = min(n, 512)
        send(f"m{addr:x},{k:x}"); r = recv_pkt()
        out += bytes.fromhex(r); addr += k; n -= k
    return out
s.sendall(b"+"); send("qSupported:swbreak+"); recv_pkt()
s.sendall(b"\x03"); recv_pkt()
raw = read_mem(0x8052F800, 0x70)
sec = read_mem(0x8052F900, 128)
send("c")
frames = struct.unpack(">I", raw[:4])[0]
names = ["sim (level script)", "DL submit", "thread5 total", "audio (t4)", "RSP", "RDP"]
print(f"perf: {frames} frames sampled")
if frames:
    budget = 33333.0  # us per 30fps frame
    for k in range(6):
        sum_cyc, max_cyc = struct.unpack(">QI", raw[8 + k*16: 8 + k*16 + 12])
        avg_us = (sum_cyc / frames) * 64 / 3000
        max_us = max_cyc * 64 / 3000
        print(f"  {names[k]:20s} avg={avg_us:8.0f} us ({100*avg_us/budget:4.1f}% of 33.3ms)  max={max_us:8.0f} us")
    snames = ["world update (802909F0)", "player-actor collision", "course actors+water",
              "camera (8001EE98)", "kart physics (80028F70)", "misc race calls",
              "netpak_frame", "net_lockstep_tick",
              "obj: func_8006E058", "obj: kart anim (80022A98x8)", "objects (80022744)", "func_8005A070",
              "ptcl pool0 (8006CEC0)", "ptcl pool3 (8006C9B8)", "ptcl pool1 (8006C6AC)", "ptcl onomat (8006D194)"]
    for k in range(16):
        sc = struct.unpack(">Q", sec[k*8:k*8+8])[0]
        avg = (sc / frames) * 64 / 3000
        print(f"  [sim] {snames[k]:22s} avg={avg:8.0f} us ({100*avg/budget:4.1f}%)")
