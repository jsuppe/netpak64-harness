import re, sys
def load(path):
    d={}; frame=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- (70|73)([0-9a-fA-F]{6})", line)
        if not m: continue
        t=m.group(1); v=int(m.group(2),16)
        if t=="70": frame=v; d.setdefault(frame,{})
        elif frame is not None: d[frame][t]=v
    return d
A=load(sys.argv[1]); B=load(sys.argv[2]); common=sorted(set(A)&set(B))
cpudiv=None
for f in common:
    if "73" in A[f] and "73" in B[f] and A[f]["73"]!=B[f]["73"]: cpudiv=f; break
print(f"common {len(common)} range {common[0]}..{common[-1]}")
print(f"CPU-AI state block (0x73) first divergence: {cpudiv}")
if cpudiv:
    for f in common:
        if cpudiv-3<=f<=cpudiv+2: print(f"  f={f} A={A[f].get('73'):#08x} B={B[f].get('73'):#08x} {'CPU!' if A[f].get('73')!=B[f].get('73') else ''}")
