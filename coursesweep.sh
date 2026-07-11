#!/bin/bash
# coursesweep.sh — 4-PLAYER race on EVERY course (inside ares-builder).
# Per course: 4 instances race it headlessly; verdict from relay diag
# (avg_rate/slow_pct per node + desync). LOSS=<pct> runs against a private
# lossy relay on :6466 to stress the stall path (desync hunting).
# Staged ROM must have gNetTestCourse (b35da524: 0x80417b74).
set -u
COURSE_ADDR=${COURSE_ADDR:-80417b74}
COURSES=${COURSES:-"00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d"}
DWELL=${DWELL:-230}
LOSS=${LOSS:-0}
RELAY=127.0.0.1:6465
if [ "$LOSS" != "0" ]; then
  pkill -f "np64-relay --bind 127.0.0.1:6466" 2>/dev/null
  /work/relay-target/release/np64-relay --bind 127.0.0.1:6466 --dev-loss $LOSS \
    --diag-dir /work/diag >/work/np64out/sweep_relay.log 2>&1 &
  RELAY=127.0.0.1:6466
  sleep 1
fi
export DISPLAY=:84
OUT=/work/np64out; mkdir -p "$OUT"
pkill -9 -f "Xvfb :84" 2>/dev/null; rm -f /tmp/.X84-lock /tmp/.X11-unix/X84
Xvfb :84 -screen 0 3200x700x24 >/dev/null 2>&1 & sleep 2
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None)

for C in $COURSES; do
  ROOM=C${C}$(date +%s | tail -c 4)
  echo "=== course 0x$C room $ROOM (loss $LOSS%) ==="
  port=9291
  for n in alice bob dave erin; do
    rm -rf "/tmp/cs_$n"; mkdir -p "/tmp/cs_$n"; rm -f "$OUT/cs_$n.log"
    HOME="/tmp/cs_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=$RELAY \
      NP64_ROOM=$ROOM NP64_NAME="$n" \
      "$ARESBIN" "${COMMON[@]}" --setting DebugServer/Enabled=true --setting DebugServer/Port=$port \
      --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/cs_$n.log" 2>&1 &
    port=$((port+1))
    sleep 3
  done
  sleep 18
  python3 /work/gdbpoke.py 9291 $COURSE_ADDR 000000$C >/dev/null 2>&1
  # wait for entry, then let the race run
  for i in $(seq 1 130); do
    sleep 1
    grep -q "io wW 0020 <- 43" "$OUT/cs_bob.log" 2>/dev/null && break
  done
  sleep $DWELL
  pkill -9 -x ares 2>/dev/null
  sleep 2
  echo "ROOM=$ROOM COURSE=$C"
done
echo SWEEP-DONE
