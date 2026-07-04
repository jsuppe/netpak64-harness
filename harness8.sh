#!/bin/bash
# Eight-instance lockstep harness: 8 ares instances pair in ONE relay room and race
# together headlessly (full MK64 grid, all 8 karts human-driven by lockstep). Each
# emits the per-frame sim hash (0x76/0x77); we diff all eight streams.
set -u
# Use a display we OWN (see harness4.sh) — big enough for a 4x2 tile of ~768x622.
export DISPLAY=:77
OUT=/work/np64out; mkdir -p "$OUT"
NAMES=(alice bob carol dave erin frank grace henry)
rm -f "$OUT"/relay8.log "$OUT"/t8_*.png
for n in "${NAMES[@]}"; do rm -f "$OUT/$n.log"; done
pkill -9 -f "Xvfb :77" 2>/dev/null; rm -f /tmp/.X77-lock /tmp/.X11-unix/X77
Xvfb :77 -screen 0 3200x1300x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1

/work/relay-target/release/np64-relay --bind 127.0.0.1:6465 --verbose >"$OUT/relay8.log" 2>&1 &
sleep 1
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None --system "Nintendo 64")

PIDS=()
for n in "${NAMES[@]}"; do
  mkdir -p "/tmp/h8_$n"
  HOME="/tmp/h8_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=TESTAB NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" /work/mk64_test.z64 >"$OUT/$n.log" 2>&1 &
  PIDS+=($!)
  sleep "${DELAY:-2}"
done

TILED=0
EVCOUNT=0
EVSHOTS=0
LASTSHOT=0
for i in $(seq 1 "${DWELL:-110}"); do
  sleep 1
  # Leaver test: kill one instance mid-race (KILL_NAME=carol KILL_AT=60)
  if [ -n "${KILL_NAME:-}" ] && [ "$i" = "${KILL_AT:-60}" ]; then
    idx=0
    for n in "${NAMES[@]}"; do
      if [ "$n" = "$KILL_NAME" ]; then kill -9 "${PIDS[$idx]}" 2>/dev/null; echo "KILLED $KILL_NAME (node $idx) at t=${i}s"; fi
      idx=$((idx+1))
    done
  fi
  for WID in $(xdotool search --name mk64 2>/dev/null | sort -u); do
    xdotool windowactivate "$WID" 2>/dev/null; xdotool key --window "$WID" Return 2>/dev/null
  done
  # Tile once, early (as soon as all 8 windows exist), so event shots are instant.
  if [ "$TILED" = 0 ] && [ "$i" -ge "${TILEAT:-40}" ]; then
    mapfile -t WINS < <(xdotool search --name mk64 2>/dev/null | sort -u)
    if [ "${#WINS[@]}" -ge 8 ]; then
      unset WIDTH HEIGHT
      eval "$(xdotool getwindowgeometry --shell "${WINS[0]}" 2>/dev/null)"
      GW=${WIDTH:-780}; GH=${HEIGHT:-640}; COLS=4; PAD=6
      echo "tiling ${#WINS[@]} windows at ${GW}x${GH} (${COLS} cols)"
      n=0
      for W in "${WINS[@]}"; do
        col=$(( n % COLS )); row=$(( n / COLS ))
        xdotool windowactivate --sync "$W" 2>/dev/null
        xdotool windowmove --sync "$W" $(( col * (GW + PAD) )) $(( row * (GH + PAD) )) 2>/dev/null
        n=$(( n + 1 ))
      done
      TILED=1
    fi
  fi
  if [ "$i" = "${SHOT1:-80}" ]; then
    scrot -o "$OUT/t8_all_i${i}.png" 2>/dev/null
  fi
  # Event-triggered shots: the ROM pokes 0x65[item<<8|slot] when a kart fires its
  # item. Watch all logs; on new events (max 6 shots, >=8s apart) capture the tile
  # ~1.5s later so the effect (shrink/star) is visible on-screen.
  if [ "$TILED" = 1 ] && [ "$EVSHOTS" -lt "${MAXEVSHOTS:-6}" ] && [ $(( i - LASTSHOT )) -ge 8 ]; then
    NEW=0
    for n in "${NAMES[@]}"; do
      c=$(grep -c 'io wW 0020 <- 59' "$OUT/$n.log" 2>/dev/null) || c=0
      NEW=$(( NEW + c ))
    done
    if [ "$NEW" -gt "$EVCOUNT" ]; then
      EVCOUNT=$NEW
      sleep 1.5
      EVSHOTS=$(( EVSHOTS + 1 ))
      LASTSHOT=$i
      scrot -o "$OUT/t8_evt${EVSHOTS}_i${i}.png" 2>/dev/null
      echo "event shot $EVSHOTS at t=${i}s (total item-use events: $NEW)"
    fi
  fi
done
for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
pkill -f "np64-relay" 2>/dev/null; sleep 1

echo "===== RELAY (who joined) ====="
grep -iE "joined room" "$OUT/relay8.log" | tail -10
echo "===== per-instance: sim hashes + stalls ====="
LOGS=()
for n in "${NAMES[@]}"; do
  LOGS+=("$OUT/$n.log")
  echo "$n: 0x77=$(grep -c 'io wW 0020 <- 77' "$OUT/$n.log")  stalls=$(grep -oE 'io wW 0020 <- 68[0-9a-fA-F]{6}' "$OUT/$n.log" | tail -1 | grep -oE '[0-9a-f]{6}$')"
done
python3 /work/decode_det4.py "${LOGS[@]}"
if [ -n "${KILL_NAME:-}" ]; then
  echo "===== SURVIVORS-ONLY comparison (post-drop determinism) ====="
  SLOGS=()
  for n in "${NAMES[@]}"; do [ "$n" = "$KILL_NAME" ] || SLOGS+=("$OUT/$n.log"); done
  python3 /work/decode_det4.py "${SLOGS[@]}"
  echo "===== drop events (0x58 [player<<16|lastFrame]) ====="
  for n in "${NAMES[@]}"; do
    [ "$n" = "$KILL_NAME" ] && continue
    echo "$n: $(grep -oiE '0020 <- 58[0-9a-f]{6}' "$OUT/$n.log" | sort -u | head -2 | tr '\n' ' ')"
  done
fi
