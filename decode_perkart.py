#!/usr/bin/env python3
# Per-kart divergence: 0x6F<frame> marks a frame, then 0x60..0x67 = kart 0..7 hash.
import re, sys
def load(path):
    d, frame = {}, None
    for line in open(path):
        m = re.search(r"io wW 0020 <- (6[0-9a-fA-F])([0-9a-fA-F]{6})", line)
        if not m: continue
        tag, val = int(m.group(1),16), int(m.group(2),16)
        if tag == 0x6F:
            frame = val; d.setdefault(frame, {})
        elif frame is not None and 0x60 <= tag <= 0x67:
            d[frame][tag-0x60] = val
    return d
A=load(sys.argv[1]); B=load(sys.argv[2])
common=sorted(set(A)&set(B))
firstdiv=None
for f in common:
    ka,kb=A[f],B[f]
    diffk=[k for k in range(8) if k in ka and k in kb and ka[k]!=kb[k]]
    if diffk and firstdiv is None:
        firstdiv=(f,diffk)
        print(f"FIRST per-kart divergence at frame {f}: karts {diffk}")
        for ff in common:
            if firstdiv[0]-3 <= ff <= firstdiv[0]+3:
                row=" ".join(f"k{k}={'!' if (k in A[ff] and k in B[ff] and A[ff][k]!=B[ff][k]) else '.'}" for k in range(8))
                print(f"  f={ff:5d}  {row}")
        break
if firstdiv is None:
    print(f"no per-kart divergence across {len(common)} common frames")
