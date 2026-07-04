import re
def load(path, t1, t2):
    d={}; fr=None
    for line in open(path):
        m=re.search(r"io wW 0020 <- ("+t1+"|"+t2+r")([0-9a-fA-F]{6})", line)
        if not m: continue
        tag,val=m.group(1),int(m.group(2),16)
        if tag==t1: fr=val
        elif fr is not None: d[fr]=val; fr=None
    return d
a_in=load("/work/np64out/alice.log","74","75"); b_in=load("/work/np64out/bob.log","74","75")
a_sim=load("/work/np64out/alice.log","76","77"); b_sim=load("/work/np64out/bob.log","76","77")
inm=[f for f in sorted(set(a_in)&set(b_in)) if a_in[f]!=b_in[f]]
simm=[f for f in sorted(set(a_sim)&set(b_sim)) if a_sim[f]!=b_sim[f]]
print("first INPUT-set mismatch:", inm[0] if inm else None, " count:", len(inm))
print("first SIM mismatch:", simm[0] if simm else None, " count:", len(simm))
for f in range(305,316):
    ia,ib,sa,sb=a_in.get(f),b_in.get(f),a_sim.get(f),b_sim.get(f)
    print(f"f={f} inA={ia and format(ia,'06x')} inB={ib and format(ib,'06x')} {'IN!' if ia!=ib else '   '} simA={sa and format(sa,'06x')} simB={sb and format(sb,'06x')} {'SIM!' if sa!=sb else ''}")
