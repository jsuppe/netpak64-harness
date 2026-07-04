import re, sys
def load(path):
    d={}; frame=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- (78|79|7a|7A)([0-9a-fA-F]{6})", line)
        if not m: continue
        tag=m.group(1).lower(); val=int(m.group(2),16)
        if tag=="78": frame=val; d.setdefault(frame,{})
        elif frame is not None: d[frame][tag]=val
    return d
A=load(sys.argv[1]); B=load(sys.argv[2])
common=sorted(set(A)&set(B))
seeddiv=itemdiv=None
for f in common:
    if seeddiv is None and "79" in A[f] and "79" in B[f] and A[f]["79"]!=B[f]["79"]: seeddiv=f
    if itemdiv is None and "7a" in A[f] and "7a" in B[f] and A[f]["7a"]!=B[f]["7a"]: itemdiv=f
print(f"common frames {len(common)}  range {common[0]}..{common[-1]}")
print(f"first SEED(0x79) divergence: {seeddiv}")
print(f"first ITEM(0x7A) divergence: {itemdiv}")
for f in common:
    if 270<=f<=284:
        a=A[f]; b=B[f]
        print(f"  f={f:4d} seedA={a.get('79'):#06x} seedB={b.get('79'):#06x} {'SEED!' if a.get('79')!=b.get('79') else ''}  itemA={a.get('7a')} itemB={b.get('7a')} {'ITEM!' if a.get('7a')!=b.get('7a') else ''}")
