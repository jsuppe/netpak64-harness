import re
def dump(p):
    b=bytearray()
    for line in open(p):
        m=re.search(r"io wW 0020 <- 5a([0-9a-fA-F]{6})",line,re.I)
        if m:
            v=int(m.group(1),16)
            b += bytes([(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF])
            if len(b)>=0xDDA: break
    return bytes(b[:0xDD8])
a=dump("/work/np64out/alice.log"); c=dump("/work/np64out/bob.log")
print(f"alice {len(a)}B bob {len(c)}B")
diffs=[(i,a[i],c[i]) for i in range(min(len(a),len(c))) if a[i]!=c[i]]
print(f"{len(diffs)} differing bytes; offsets:")
# group into ranges
runs=[];
for i,(off,x,y) in enumerate(diffs):
    if runs and off==runs[-1][1]+1: runs[-1][1]=off
    else: runs.append([off,off])
for r in runs[:20]:
    print(f"  0x{r[0]:03X}-0x{r[1]:03X}  alice={a[r[0]:r[1]+1].hex()} bob={c[r[0]:r[1]+1].hex()}")
