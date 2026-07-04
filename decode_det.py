#!/usr/bin/env python3
# Compare two determinism-probe logs. Each logs (frame,hash) as poke pairs:
#   io wW 0020 <- 76<frame24>   then   io wW 0020 <- 77<hash24>
# Aligns by race-frame and reports the first divergence.
import re, sys

def load(path):
    d, frame = {}, None
    for line in open(path):
        m = re.search(r"io wW 0020 <- (76|77)([0-9a-fA-F]{6})", line)
        if not m:
            continue
        tag, val = m.group(1), int(m.group(2), 16)
        if tag == "76":
            frame = val
        elif frame is not None:
            d[frame] = val
            frame = None
    return d

A = load(sys.argv[1]); B = load(sys.argv[2])
common = sorted(set(A) & set(B))
if not common:
    print(f"NO COMMON FRAMES (A={len(A)} B={len(B)}) — instances never reached an aligned race")
    sys.exit(0)
mism = [f for f in common if A[f] != B[f]]
print(f"frames compared: {len(common)}  (A={len(A)} B={len(B)})  range {common[0]}..{common[-1]}")
if not mism:
    print(">>> IDENTICAL across every compared frame — DETERMINISTic. Lockstep is viable.")
else:
    fd = mism[0]
    print(f">>> DIVERGES. first mismatch at frame {fd}: A={A[fd]:06x} B={B[fd]:06x}")
    print(f"    matched {len(common)-len(mism)}/{len(common)} frames before/around divergence")
    for f in common:
        if fd - 4 <= f <= fd + 4:
            print(f"    f={f:5d}  A={A[f]:06x}  B={B[f]:06x}  {'<-- DIVERGE' if A[f]!=B[f] else ''}")
