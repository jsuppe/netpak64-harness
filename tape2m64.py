#!/usr/bin/env python3
"""tape2m64.py — convert a NET_DIAG input tape (tapedump.py output) into a
Mupen64 .m64 movie for one kart, so the drive can be scrubbed in standard
tooling. Note: the movie is a VIEWING/analysis artifact — replay verification
happens in our own harness (the .m64 won't sync against vanilla MK64: our ROM
reaches the race through different menus).

Usage: tape2m64.py <in.tape> <kart 0-7> <out.m64>

Button mapping libultra CONT_* (tape) -> mupen .m64 bit layout.
"""
import struct
import sys

inp, kart, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
raw = open(inp, "rb").read()
magic, frames, players, course = struct.unpack(">IIII", raw[:16])
assert magic == 0x4E545031, "not a tape"
data = raw[16:]

# libultra mask -> mupen bit
M = [
    (0x8000, 7),   # A
    (0x4000, 6),   # B
    (0x2000, 5),   # Z
    (0x1000, 4),   # START
    (0x0800, 3),   # D-up
    (0x0400, 2),   # D-down
    (0x0200, 1),   # D-left
    (0x0100, 0),   # D-right
    (0x0020, 13),  # L
    (0x0010, 12),  # R
    (0x0008, 11),  # C-up
    (0x0004, 10),  # C-down
    (0x0002, 9),   # C-left
    (0x0001, 8),   # C-right
]

hdr = bytearray(1024)
hdr[0:4] = b"M64\x1a"
struct.pack_into("<I", hdr, 0x04, 3)          # version
struct.pack_into("<I", hdr, 0x08, 0x4E503634)  # uid 'NP64'
struct.pack_into("<I", hdr, 0x0C, frames)      # VI frame count (approx)
struct.pack_into("<I", hdr, 0x10, 0)           # rerecords
hdr[0x14] = 60                                 # fps
hdr[0x15] = 1                                  # controllers
struct.pack_into("<I", hdr, 0x18, frames)      # input samples
struct.pack_into("<H", hdr, 0x1C, 2)           # start from power-on
struct.pack_into("<I", hdr, 0x20, 1)           # controller 1 present
hdr[0xC4:0xC4 + 32] = b"MARIO KART 64 NETPAK".ljust(32, b"\x00")
hdr[0x222:0x222 + 20] = b"netpak-tape".ljust(20, b"\x00")
author = f"NetPak64 tape kart {kart} course {course}".encode()
hdr[0x300:0x300 + len(author)] = author

body = bytearray()
for f in range(frames):
    o = (f * 8 + kart) * 4
    btn = (data[o] << 8) | data[o + 1]
    sx = data[o + 2]
    sy = data[o + 3]
    m = 0
    for mask, bit in M:
        if btn & mask:
            m |= 1 << bit
    body += struct.pack("<H", m) + bytes([sx, sy])

open(out, "wb").write(bytes(hdr) + bytes(body))
print(f"{out}: {frames} frames, kart {kart}, course {course}")
