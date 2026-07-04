#!/usr/bin/env python3
# Compare N (2-4) lockstep sim-hash streams. Each logs (frame,hash) as poke pairs:
#   io wW 0020 <- 76<frame24>  then  io wW 0020 <- 77<hash24>
# Aligns by logical frame and reports the first frame where the streams disagree.
import re, sys

def load(path):
    d, frame = {}, None
    try:
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
    except FileNotFoundError:
        pass
    return d

paths = sys.argv[1:]
streams = [(p.split('/')[-1], load(p)) for p in paths]
present = [(n, d) for n, d in streams if d]
print(f"instances with data: {len(present)}/{len(streams)}  " +
      "  ".join(f"{n}={len(d)}" for n, d in streams))
if len(present) < 2:
    print(">>> fewer than 2 instances produced a race hash — pairing/launch failed")
    sys.exit(0)

# common frames across all present streams
common = None
for _, d in present:
    common = set(d) if common is None else (common & set(d))
common = sorted(common)
if not common:
    print(">>> NO COMMON FRAMES across the instances — they never reached an aligned race")
    sys.exit(0)

ref_name, ref = present[0]
mism = [f for f in common if any(d[f] != ref[f] for _, d in present[1:])]
print(f"frames compared: {len(common)}  range {common[0]}..{common[-1]}  (ref={ref_name})")
if not mism:
    print(f">>> ALL {len(present)} INSTANCES IDENTICAL across every compared frame — {len(present)}p lockstep is deterministic.")
else:
    fd = mism[0]
    print(f">>> DIVERGES. first mismatch at frame {fd}:")
    for n, d in present:
        print(f"      {n} = {d[fd]:06x}")
    print(f"    matched {len(common)-len(mism)}/{len(common)} common frames")
