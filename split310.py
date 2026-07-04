import re,sys
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
print("hash at frame 310:", {n:format(ds[n].get(310,0),'06x') for n in names})
# majority group
from collections import Counter
c=Counter(ds[n].get(310) for n in names)
maj=c.most_common(1)[0][0]
group=[n for n in names if ds[n].get(310)==maj]
print("majority group:",group)
common=None
for n in group:
    common=set(ds[n]) if common is None else common&set(ds[n])
common=sorted(common)
mism=[f for f in common if len({ds[n][f] for n in group})>1]
print(f"majority-group compare: {len(common)} frames, range {common[0]}..{common[-1]}, mismatches={len(mism)}")
print("IDENTICAL post-drop across majority group" if not mism else f"first mismatch {mism[0]}")
# kart-2 (dropped) still racing? distinct per-kart 0x62 hashes after L=399 in alice
k2=set()
fr=None
for line in open("/work/np64out/alice.log"):
    m=re.search(r"io wW 0020 <- 6f([0-9a-fA-F]{6})",line,re.I)
    if m: fr=int(m.group(1),16); continue
    m=re.search(r"io wW 0020 <- 62([0-9a-fA-F]{6})",line,re.I)
    if m and fr is not None and fr>420: k2.add(m.group(1))
print(f"kart-2 distinct hashes after drop (frames >420): {len(k2)} -> {'RACING as bot' if len(k2)>50 else 'parked/frozen?'}")
