import re, sys
def load(path):
    d={}; frame=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- (74|75)([0-9a-fA-F]{6})", line)
        if not m: continue
        tag=m.group(1); val=int(m.group(2),16)
        if tag=="74": frame=val; 
        elif frame is not None: d[frame]=val; frame=None
    return d
A=load(sys.argv[1]); B=load(sys.argv[2])
common=sorted(set(A)&set(B))
mism=[f for f in common if A[f]!=B[f]]
print(f"input-set hash: {len(common)} common, range {common[0]}..{common[-1]}")
if not mism: print(">>> input sets IDENTICAL every frame (transport perfect; divergence is NOT inputs)")
else:
    print(f">>> input sets DIVERGE, first at frame {mism[0]}  (A={A[mism[0]]:06x} B={B[mism[0]]:06x})")
    print(f"    {len(mism)} mismatched frames of {len(common)}")
    for f in common:
        if mism[0]-3<=f<=mism[0]+5: print(f"    f={f:4d} A={A[f]:06x} B={B[f]:06x} {'<-- INPUT DIVERGE' if A[f]!=B[f] else ''}")
