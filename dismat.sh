#!/bin/bash
# dismat.sh — DISRUPTION MATRIX runner (inside ares-builder container).
# Happy path + exactly ONE injected disruption; verdict from relay diag JSONL.
#
#   SCEN=baseline          nothing injected (control)
#   SCEN=kill-alice-mid    kill the HOST mid-race
#   SCEN=kill-bob-mid      kill a JOINER mid-race
#   SCEN=kill-wanda-mid    kill the SPECTATOR mid-race (should be a non-event)
#   SCEN=kill-bob-entry    kill a joiner during race entry (block window)
#   SCEN=pause-bob         joiner pauses mid-race, resumes after ~10s
#   SCEN=pause-alice       host pauses mid-race
#   SCEN=pause-long-bob    joiner pauses ~40s (must NOT be dropped: keep-alive)
#
# Instances: alice(host, self-starts), bob(racer), wanda(spectator, Z+A join).
# GDB stubs 9271/9272/9273 for the pause pokes (gNetTestPauseAt/Len).
set -u
SCEN=${SCEN:-baseline}
PAUSE_AT=${PAUSE_AT:-80421b7c}   # override per staged ROM: gNetTestPauseAt
PAUSE_LEN=${PAUSE_LEN:-80421b80} # gNetTestPauseLen
DWELL=${DWELL:-200}
export DISPLAY=:82
OUT=/work/np64out; mkdir -p "$OUT"
NAMES=(alice bob wanda)
ROOM=DM$(date +%s | tail -c 5)
pkill -9 -f "Xvfb :82" 2>/dev/null; rm -f /tmp/.X82-lock /tmp/.X11-unix/X82
Xvfb :82 -screen 0 2400x700x24 >/dev/null 2>&1 & sleep 2
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None)

declare -A PIDS
port=9271
for n in "${NAMES[@]}"; do
  rm -rf "/tmp/dm_$n"; mkdir -p "/tmp/dm_$n"; rm -f "$OUT/dm_$n.log"
  HOME="/tmp/dm_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 \
    NP64_ROOM=$ROOM NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" --setting DebugServer/Enabled=true --setting DebugServer/Port=$port \
    --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/dm_$n.log" 2>&1 &
  PIDS[$n]=$!
  port=$((port+1))
  sleep 3
done
echo "== dismat $SCEN room $ROOM =="

# wait for the race (block-done poke 0x43 on bob)
RACING_AT=0
for i in $(seq 1 $DWELL); do
  sleep 1
  if grep -q "io wW 0020 <- 43" "$OUT/dm_bob.log" 2>/dev/null; then RACING_AT=$i; break; fi
done
[ "$RACING_AT" = 0 ] && { echo "DISMAT-FAIL (race never started)"; pkill -9 -x ares; exit 1; }
echo "race entered at t=${RACING_AT}s"

case "$SCEN" in
  baseline) ;;
  kill-alice-mid)  sleep 20; kill -9 "${PIDS[alice]}"; echo "killed alice" ;;
  kill-bob-mid)    sleep 20; kill -9 "${PIDS[bob]}";   echo "killed bob" ;;
  kill-wanda-mid)  sleep 20; kill -9 "${PIDS[wanda]}"; echo "killed wanda" ;;
  kill-bob-entry)  kill -9 "${PIDS[bob]}"; echo "killed bob at entry" ;;
  pause-bob)       sleep 15; python3 /work/gdbpoke.py 9272 $PAUSE_AT 00000200 ;;
  pause-alice)     sleep 15; python3 /work/gdbpoke.py 9271 $PAUSE_AT 00000200 ;;
  pause-long-bob)  sleep 15; python3 /work/gdbpoke.py 9272 $PAUSE_LEN 000004b0 $PAUSE_AT 00000200 ;;
  *) echo "unknown SCEN"; ;;
esac

sleep $((DWELL - RACING_AT > 60 ? DWELL - RACING_AT : 60)) 2>/dev/null || sleep 90
pkill -9 -x ares 2>/dev/null

echo "== verdict inputs (room $ROOM) =="
echo "pause markers: $(grep -hoE 'io wW 0020 <- a[567][0-9a-f]{6}' $OUT/dm_*.log 2>/dev/null | sort -u | tr '\n' ' ')"
for n in "${NAMES[@]}"; do
  echo "$n hashes: $(grep -c 'io wW 0020 <- 77' "$OUT/dm_$n.log" 2>/dev/null)"
done
echo "ROOM=$ROOM"
echo DISMAT-DONE
