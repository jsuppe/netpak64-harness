import re, sys
def load(path):
    d={}; frame=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- (70|71|72)([0-9a-fA-F]{6})", line)
        if not m: continue
        t=m.group(1); v=int(m.group(2),16)
        if t=="70": frame=v; d.setdefault(frame,{})
        elif frame is not None: d[frame][t]=v
    return d
A=load(sys.argv[1]); B=load(sys.argv[2]); common=sorted(set(A)&set(B))
objdiv=timerdiv=None
for f in common:
    if objdiv is None and "71" in A[f] and "71" in B[f] and A[f]["71"]!=B[f]["71"]: objdiv=f
    if timerdiv is None and "72" in A[f] and "72" in B[f] and A[f]["72"]!=B[f]["72"]: timerdiv=f
print(f"common {len(common)} range {common[0]}..{common[-1]}")
print(f"OBJECT POOL (0x71) first divergence: {objdiv}")
print(f"gCourseTimer (0x72) first divergence: {timerdiv}")
if objdiv:
    for f in common:
        if objdiv-3<=f<=objdiv+2:
            print(f"  f={f} objA={A[f].get('71'):#08x} objB={B[f].get('71'):#08x} {'OBJ!' if A[f].get('71')!=B[f].get('71') else ''}")
