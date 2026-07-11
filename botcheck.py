#!/usr/bin/env python3
# botcheck.py <alice_log> — decode rank/progress + ASCII full-track trail.
import re, sys
log = sys.argv[1]
pat = re.compile(r'io wW 0020 <- ([0-9a-f]{8})')
def s16(v): return v-0x10000 if v>=0x8000 else v
wpx,wpz=[],[]; botx,botz=[],[]; pend_wx=None; pend_kx=None
ranks=[]; laps=[]; paths=[]
for line in open(log, errors='ignore'):
    m=pat.search(line)
    if not m: continue
    v=int(m.group(1),16); tag=v>>24; val=v&0xFFFF
    if tag==0x9E: pend_wx=s16(val)
    elif tag==0x9F and pend_wx is not None: wpx.append(pend_wx); wpz.append(s16(val)); pend_wx=None
    elif tag==0x80: pend_kx=s16(val)
    elif tag==0x90 and pend_kx is not None: botx.append(pend_kx); botz.append(s16(val)); pend_kx=None
    elif tag==0x5d and (val>>8&0xff): pass
    elif (v>>16)==0x5d00: ranks.append((v>>8)&0xff)
    elif tag==0x5e: laps.append(((v>>16)&0xf)-1); paths.append(v&0xffff)
if ranks: print(f"RANK best={min(ranks)} final={ranks[-1]} n={len(ranks)}")
if laps:  print(f"PROGRESS max_lap={max(laps)} distinct_paths={len(set(paths))}/{len(wpx)} final=lap{laps[-1]} path{paths[-1]}")
if not wpx or not botx: sys.exit()
minx,maxx=min(wpx),max(wpx); minz,maxz=min(wpz),max(wpz)
W,H=76,32
def g(x,z): return int((x-minx)/(maxx-minx+1)*(W-1)), int((z-minz)/(maxz-minz+1)*(H-1))
grid=[[' ']*W for _ in range(H)]
for i in range(len(wpx)):
    gx,gz=g(wpx[i],wpz[i])
    if 0<=gx<W and 0<=gz<H: grid[gz][gx]='.'
n=len(botx)
for j,i in enumerate(range(0,n,max(1,n//24))):
    gx,gz=g(botx[i],botz[i])
    if 0<=gx<W and 0<=gz<H: grid[gz][gx]=chr(ord('a')+min(j,25))
print("full track: '.'=waypoints  a..z=bot over race time (a=start, z=end)")
for row in grid: print(''.join(row))
