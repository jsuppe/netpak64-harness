import re
names=["alice","bob","carol","dave","erin","frank","grace","henry"]
def load(p):
    d={};fr=None
    for line in open(p):
        m=re.search(r"io wW 0020 <- (76|5b|5c)([0-9a-fA-F]{6})",line,re.I)
        if not m: continue
        t,v=m.group(1).lower(),int(m.group(2),16)
        if t=="76": fr=v; d.setdefault(fr,{})
        elif fr is not None: d[fr][t]=v
    return d
ds={n:load(f"/work/np64out/{n}.log") for n in names}
common=None
for n in names: common=set(ds[n]) if common is None else common&set(ds[n])
for tag,label in [("5b","cam-arrays"),("5c","objpool")]:
    first=None
    for f in sorted(common):
        if len({ds[n][f].get(tag) for n in names})>1: first=f; break
    print(f"{label}: first divergence {first}")
