#!/usr/bin/env python3
# Decode the NetPak64 debug state-dump from an ares NP64_TRACE_IO log.
# The ROM pokes tagged 32-bit words to device reg 0x0020; ares logs each as
# "io wW 0020 <- <hex>". This turns them back into a readable race timeline.
#
#   usage: decode_npdbg.py < ares.log       (or: decode_npdbg.py ares.log)
import sys, re

GS = {0: "MENU", 4: "RACING", 5: "ENDING", 9: "CREDITS", 0xff: "boot", 0xffff: "init"}
TAG = re.compile(r"io wW 0020 <- ([0-9a-fA-F]{8})")

def main(src):
    f = None  # current in-race frame
    t = None  # (stg, go, type)
    for line in src:
        m = TAG.search(line)
        if not m:
            continue
        v = int(m.group(1), 16)
        tag = v >> 24
        if tag == 0x51:
            gs, mode, crs = (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF
            print(f"[state] gamestate={gs} ({GS.get(gs,'?')})  mode={mode}  course={crs}")
        elif tag == 0x52:
            f = v & 0xFFFFFF
        elif tag == 0x53:
            t = ((v >> 17) & 1, (v >> 16) & 1, v & 0xFFFF)
        elif tag == 0x54:
            crs, spd = (v >> 16) & 0xFF, v & 0xFFFF
            stg, go, typ = t if t else (0, 0, 0)
            drv = "DRIVABLE" if (go and not stg) else ("staging" if stg else "countdown")
            print(f"    f={f} type={typ:04x} stg={stg} go={go} spd={spd/10:.1f} crs={crs}  [{drv}]")
        elif tag == 0x5F:
            print(f"*** STUCK: player0 still staging/countdown at f=240 type={v & 0xFFFF:04x}")
        # navigator breadcrumbs (optional, low-noise)
        elif tag == 0xE0:
            pass  # screen id — uncomment to trace menu flow
        elif tag == 0xF0:
            pass  # online step

if __name__ == "__main__":
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as fh:
            main(fh)
    else:
        main(sys.stdin)
