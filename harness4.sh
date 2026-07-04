#!/bin/bash
# Four-instance lockstep harness: 4 ares instances run mk64_test.z64, auto-navigate
# ONLINE -> JOIN (preset room TESTAB) -> self-START, so they pair in ONE relay room
# and race together headlessly. Each emits the per-frame sim hash (0x76/0x77); we
# diff all four streams to check the 4-player lockstep stays bit-identical.
set -u
# Use a display we fully OWN (a fresh number), not the pre-existing :99 — that one
# is a shared/host X locked at 1280x720, so its -screen size is ignored and scrot
# only ever captures 1280x720. On our own display the size takes and scrot grabs
# the whole thing, so 4 windows tile 2x2 in one shot.
export DISPLAY=:77
OUT=/work/np64out; mkdir -p "$OUT"
rm -f "$OUT"/relay4.log "$OUT"/a4.log "$OUT"/b4.log "$OUT"/c4.log "$OUT"/d4.log "$OUT"/t4_*.png
pkill -9 -f "Xvfb :77" 2>/dev/null; rm -f /tmp/.X77-lock /tmp/.X11-unix/X77
# Big virtual screen so 4 ares windows (~768x622 each) tile 2x2 without overlap.
Xvfb :77 -screen 0 1800x1500x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1

/work/relay-target/release/np64-relay --bind 127.0.0.1:6465 --verbose >"$OUT/relay4.log" 2>&1 &
sleep 1
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None --system "Nintendo 64")

launch() { # $1=home $2=name $3=logfile
  mkdir -p "$1"
  HOME="$1" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=TESTAB NP64_NAME="$2" \
    "$ARESBIN" "${COMMON[@]}" /work/mk64_test.z64 >"$3" 2>&1 &
}

launch /tmp/h4A alice "$OUT/a4.log"; PA=$!; sleep "${DELAY:-2}"
launch /tmp/h4B bob   "$OUT/b4.log"; PB=$!; sleep "${DELAY:-2}"
launch /tmp/h4C carol "$OUT/c4.log"; PC=$!; sleep "${DELAY:-2}"
launch /tmp/h4D dave  "$OUT/d4.log"; PD=$!

for i in $(seq 1 "${DWELL:-95}"); do
  sleep 1
  for WID in $(xdotool search --name mk64 2>/dev/null | sort -u); do
    xdotool windowactivate "$WID" 2>/dev/null; xdotool key --window "$WID" Return 2>/dev/null
  done
  if [ "$i" = "${SHOT1:-60}" ]; then
    # Tile every ares window into a 2-column grid at each window's REAL size (ares
    # won't shrink below its content, so we place, not resize), then take ONE
    # full-screen shot that captures all instances at once.
    mapfile -t WINS < <(xdotool search --name mk64 2>/dev/null | sort -u)
    unset WIDTH HEIGHT
    eval "$(xdotool getwindowgeometry --shell "${WINS[0]}" 2>/dev/null)"
    GW=${WIDTH:-780}; GH=${HEIGHT:-700}; COLS=2; PAD=8
    echo "tiling ${#WINS[@]} windows at ${GW}x${GH} each (${COLS} cols)"
    n=0
    for W in "${WINS[@]}"; do
      col=$(( n % COLS )); row=$(( n / COLS ))
      xdotool windowactivate --sync "$W" 2>/dev/null
      xdotool windowmove --sync "$W" $(( col * (GW + PAD) )) $(( row * (GH + PAD) )) 2>/dev/null
      n=$(( n + 1 ))
    done
    sleep 1
    scrot -o "$OUT/t4_all_i${i}.png" 2>/dev/null
    python3 - "$OUT/t4_all_i${i}.png" <<'PY'
import struct, sys
f=open(sys.argv[1],'rb'); f.read(16); w,h=struct.unpack('>II', f.read(8))
print(f"captured {sys.argv[1].split('/')[-1]}: {w}x{h}")
PY
  fi
done
kill $PA $PB $PC $PD 2>/dev/null; pkill -f "np64-relay" 2>/dev/null; sleep 1

echo "===== RELAY (who joined the room) ====="
grep -iE "joined room|moved to room|left room" "$OUT/relay4.log" | tail -12
echo "===== sim-hash counts (0x77) per instance ====="
for f in a4 b4 c4 d4; do
  echo "$f: $(grep -c 'io wW 0020 <- 77' "$OUT/$f.log")  stalls: $(grep -oE 'io wW 0020 <- 68[0-9a-fA-F]{6}' "$OUT/$f.log" | tail -1)"
done
echo "===== player-count samples (0x53 low byte = type incl human count is indirect) ====="
python3 /work/decode_det4.py "$OUT/a4.log" "$OUT/b4.log" "$OUT/c4.log" "$OUT/d4.log"
