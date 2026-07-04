# Re-derive per-field: we only have the combined per-kart hash (0x60). Instead,
# dump kart0 pos/rot/speed via new tags if present; else report the 8-field combined.
# Here: compare the low-level narrow kart-0 hash (0x60) frame-by-frame is already known.
# This script instead shows the FIRST diverging quarter's frame precisely.
import re,sys
def load(path):
    d={}; frame=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- (7[bcdefBCDEF])([0-9a-fA-F]{6})",line)
        if not m: continue
        t=m.group(1).lower(); v=int(m.group(2),16)
        if t=="7b": frame=v; d.setdefault(frame,{})
        elif frame is not None: d[frame][t]=v
    return d
A=load(sys.argv[1]); B=load(sys.argv[2]); common=sorted(set(A)&set(B))
for f in common:
    if 322<=f<=334:
        row=" ".join(f"{q.upper()}={'!' if (q in A[f] and q in B[f] and A[f][q]!=B[f][q]) else '.'}" for q in ["7c","7d","7e","7f"])
        print(f"  f={f} {row}")
