import re
names=["alice","bob","carol","dave","erin","frank","grace","henry"]
def load(p):
    d={};fr=None
    for line in open(p):
        m=re.search(r"io wW 0020 <- (76|5c)([0-9a-fA-F]{6})",line,re.I)
        if not m: continue
        t,v=m.group(1).lower(),int(m.group(2),16)
        if t=="76": fr=v; d.setdefault(fr,{})
        else:
            sl=v>>20
            d[fr][sl]=v&0xFFFFF
    return d
ds={n:load(f"/work/np64out/{n}.log") for n in names}
common=None
for n in names: common=set(ds[n]) if common is None else common&set(ds[n])
firsts={}
for f in sorted(common):
    for sl in range(16):
        if sl in firsts: continue
        if len({ds[n][f].get(sl) for n in names})>1: firsts[sl]=f
per=(0x226+15)//16
for sl in sorted(firsts,key=lambda x:firsts[x])[:6]:
    print(f"slice {sl} (objects {sl*per}-{min((sl+1)*per,0x226)-1}): first diverges frame {firsts[sl]}")
