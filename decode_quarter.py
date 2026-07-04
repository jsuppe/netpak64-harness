import re, sys
def load(path):
    d={}; frame=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- (7[bcdefBCDEF])([0-9a-fA-F]{6})", line)
        if not m: continue
        tag=m.group(1).lower(); val=int(m.group(2),16)
        if tag=="7b": frame=val; d.setdefault(frame,{})
        elif frame is not None: d[frame][tag]=val
    return d
A=load(sys.argv[1]); B=load(sys.argv[2])
common=sorted(set(A)&set(B))
qnames={"7c":"Q0[0x000-376]","7d":"Q1[0x376-6EC]","7e":"Q2[0x6EC-A62]","7f":"Q3[0xA62-DD8]"}
first={q:None for q in qnames}
for f in common:
    for q in qnames:
        if first[q] is None and q in A[f] and q in B[f] and A[f][q]!=B[f][q]:
            first[q]=f
print(f"common {len(common)} range {common[0]}..{common[-1]}")
for q in ["7c","7d","7e","7f"]:
    print(f"  {qnames[q]} first divergence: {first[q]}")
