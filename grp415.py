import re
from collections import Counter
def load(p):
    d={};fr=None
    for line in open(p):
        m=re.search(r"io wW 0020 <- (76|77)([0-9a-fA-F]{6})",line)
        if not m: continue
        t,v=m.group(1),int(m.group(2),16)
        if t=="76": fr=v
        elif fr is not None: d[fr]=v; fr=None
    return d
names=["alice","bob","dave","erin","frank","grace","henry"]
ds={n:load(f"/work/np64out/{n}.log") for n in names}
c=Counter(ds[n].get(310) for n in names)
for val,_ in c.most_common():
    grp=[n for n in names if ds[n].get(310)==val]
    common=None
    for n in grp: common=set(ds[n]) if common is None else common&set(ds[n])
    common=sorted(common)
    mism=[f for f in common if len({ds[n][f] for n in grp})>1]
    print(f"group({format(val,'06x')}): {grp}")
    print(f"  frames {common[0]}..{common[-1]}, mismatches={len(mism)}" + (f", first={mism[0]}" if mism else " -> IDENTICAL incl. drop boundary 415->416 ✓"))
