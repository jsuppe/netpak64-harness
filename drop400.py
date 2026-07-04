import re
def loadsim(p):
    d={};fr=None
    for line in open(p):
        m=re.search(r"io wW 0020 <- (76|77)([0-9a-fA-F]{6})",line)
        if not m: continue
        t,v=m.group(1),int(m.group(2),16)
        if t=="76": fr=v
        elif fr is not None: d[fr]=v; fr=None
    return d
def loadkart(p):
    d={};fr=None
    for line in open(p):
        m=re.search(r"io wW 0020 <- 6f([0-9a-fA-F]{6})",line,re.I)
        if m: fr=int(m.group(1),16); d.setdefault(fr,{}); continue
        m=re.search(r"io wW 0020 <- 6([0-7])([0-9a-fA-F]{6})",line)
        if m and fr is not None: d[fr][int(m.group(1))]=m.group(2)
    return d
names=["alice","bob","dave","erin","henry"]
sim={n:loadsim(f"/work/np64out/{n}.log") for n in names}
print("sim hash at 400:", {n:format(sim[n].get(400,0),'06x') for n in names})
ka={n:loadkart(f"/work/np64out/{n}.log") for n in names}
for f in (400,401,402):
    for k in range(8):
        vals={n:ka[n].get(f,{}).get(k) for n in names}
        if len(set(vals.values()))>1:
            print(f"frame {f} kart {k} SPLIT: {vals}")
