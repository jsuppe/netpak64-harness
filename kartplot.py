#!/usr/bin/env python3
"""kartplot.py <ares_log> <out.svg> — plot course waypoints + all 8 kart trails
from the NP64_TRACE_IO poke log (tags 0x9E/9F waypoints, 0x80+k/0x90+k kart x/z)."""
import re, sys

log, out = sys.argv[1], sys.argv[2]
pat = re.compile(r'io wW 0020 <- ([0-9a-f]{8})')
wpx, wpz = [], []
trails = [[] for _ in range(8)]
pend_wx = None
pend_kx = {}
def s16(v): return v - 0x10000 if v >= 0x8000 else v
for line in open(log, errors='ignore'):
    m = pat.search(line)
    if not m: continue
    v = int(m.group(1), 16); tag = v >> 24; val = s16(v & 0xFFFF)
    if tag == 0x9E: pend_wx = val
    elif tag == 0x9F and pend_wx is not None: wpx.append(pend_wx); wpz.append(val); pend_wx = None
    elif 0x80 <= tag <= 0x87: pend_kx[tag & 7] = val
    elif 0x90 <= tag <= 0x97:
        k = tag & 7
        if k in pend_kx: trails[k].append((pend_kx.pop(k), val))
allx = wpx + [p[0] for t in trails for p in t]
allz = wpz + [p[1] for t in trails for p in t]
if not allx: sys.exit("no data")
x0, x1, z0, z1 = min(allx), max(allx), min(allz), max(allz)
W = 900.0; S = (W - 40) / max(x1 - x0, z1 - z0, 1); H = (z1 - z0) * S + 40
def X(x): return 20 + (x - x0) * S
def Z(z): return 20 + (z - z0) * S
cols = ['#ff3030','#30a0ff','#30d030','#e0d020','#d060ff','#20d0c0','#ff9020','#a0a0a0']
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" style="background:#111">']
svg.append('<polyline fill="none" stroke="#555" stroke-width="6" points="'
           + ' '.join(f'{X(a):.1f},{Z(b):.1f}' for a, b in zip(wpx, wpz)) + '"/>')
for k, t in enumerate(trails):
    if len(t) < 2: continue
    svg.append(f'<polyline fill="none" stroke="{cols[k]}" stroke-width="1.5" points="'
               + ' '.join(f'{X(a):.1f},{Z(b):.1f}' for a, b in t) + '"/>')
    a, b = t[-1]
    svg.append(f'<circle cx="{X(a):.1f}" cy="{Z(b):.1f}" r="5" fill="{cols[k]}"/>'
               f'<text x="{X(a)+8:.1f}" y="{Z(b)+4:.1f}" fill="{cols[k]}" font-size="13">K{k}</text>')
svg.append(f'<text x="20" y="{H-8:.0f}" fill="#888" font-size="12">gray=waypoint path; K0..K7 trails; dot=final position; {len(wpx)} waypoints</text>')
svg.append('</svg>')
open(out, 'w').write('\n'.join(svg))
print(f"{out}: {len(wpx)} waypoints, trail lengths " + ' '.join(str(len(t)) for t in trails))
