import re
from collections import Counter
names=["alice","bob","carol","dave","erin","frank","grace","henry"]
def load(p):
    d={};fr=None
    for line in open(p):
        m=re.search(r"io wW 0020 <- 6f([0-9a-fA-F]{6})",line,re.I)
        if m: fr=int(m.group(1),16); d.setdefault(fr,{}); continue
        m=re.search(r"io wW 0020 <- 6([0-7])([0-9a-fA-F]{6})",line)
        if m and fr is not None:
            k=int(m.group(1)); v=int(m.group(2),16); q=v>>22
            d[fr][(k,q)]=v&0x3FFFFF
    return d
ds={n:load(f"/work/np64out/{n}.log") for n in names}
common=None
for n in names: common=set(ds[n]) if common is None else common&set(ds[n])
common=sorted(common)
# find, for each (kart,quarter), the FIRST frame where consoles disagree
firsts={}
for f in common:
    for k in range(8):
        for q in range(4):
            key=(k,q)
            vals={ds[n][f].get(key) for n in names}
            if len(vals)>1 and key not in firsts:
                firsts[key]=f
for key in sorted(firsts,key=lambda x:firsts[x])[:8]:
    print(f"kart {key[0]} Q{key[1]}: first differs at frame {firsts[key]}")
# who's the odd console at the earliest event
key=min(firsts,key=lambda x:firsts[x]); f0=firsts[key]
c=Counter(ds[n][f0].get(key) for n in names)
maj=c.most_common(1)[0][0]
odd=[n for n in names if ds[n][f0].get(key)!=maj]
print(f"earliest: kart{key[0]} Q{key[1]} @ {f0}; odd console(s): {odd}")
