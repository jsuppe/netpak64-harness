#!/usr/bin/env python3
"""tapedump.py — pull the NET_DIAG input tape out of a running ares via the
GDB stub. Halts emulation for the duration of the read (fast), then resumes.

Tape layout (net_race.c, task #35): at 0x80440000
  { u32 magic 'NTP1'; u32 frames; u32 players; u32 course; }
  then frames x 8 karts x 4 bytes {btn_hi, btn_lo, stickX, stickY}.

Usage: tapedump.py <port> <out.tape>
Out file: 16-byte header verbatim + data.
"""
import socket
import struct
import sys

TAPE_BASE = 0x80440000

port, out = int(sys.argv[1]), sys.argv[2]

def csum(p):
    return sum(p.encode()) & 0xFF

def send(s, p):
    s.sendall(f"${p}#{csum(p):02x}".encode())

def recv_pkt(s, timeout=5.0):
    s.settimeout(timeout)
    buf = b""
    while True:
        c = s.recv(65536)
        if not c:
            return None
        buf += c
        i = buf.find(b"$")
        if i >= 0:
            j = buf.find(b"#", i)
            if j >= 0 and len(buf) >= j + 3:
                s.sendall(b"+")
                return buf[i + 1:j].decode()

def read_mem(s, addr, length):
    data = b""
    while length > 0:
        n = min(length, 512)
        send(s, f"m{addr:x},{n:x}")
        r = recv_pkt(s)
        if r is None or r.startswith("E"):
            raise RuntimeError(f"read failed @0x{addr:x}: {r}")
        data += bytes.fromhex(r)
        addr += n
        length -= n
    return data

s = socket.create_connection(("::1", port), timeout=5)
s.sendall(b"+")
send(s, "qSupported:swbreak+")
recv_pkt(s)
s.sendall(b"\x03")  # halt
recv_pkt(s)

hdr = read_mem(s, TAPE_BASE, 16)
magic, frames, players, course = struct.unpack(">IIII", hdr)
if magic != 0x4E545031:
    print(f"NO TAPE (magic 0x{magic:08x})")
    send(s, "c")
    sys.exit(1)
print(f"tape: frames={frames} players={players} course={course}")
data = read_mem(s, TAPE_BASE + 16, frames * 8 * 4)
with open(out, "wb") as f:
    f.write(hdr + data)
print(f"wrote {out} ({16 + len(data)} bytes)")
send(s, "c")  # resume
s.close()
