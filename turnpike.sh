#!/bin/bash
# turnpike.sh — Toad's Turnpike desync + perf hunt (inside ares-builder).
# 2 racers; the HOST is poked to force course COURSE=<id> (default 10 =
# Toad's Turnpike, gNetTestCourse @ $COURSE_ADDR of the staged ROM).
# After the race ramps, perfdump gives the section-level sim breakdown.
set -u
COURSE=${COURSE:-0a}
COURSE_ADDR=${COURSE_ADDR:-80417b74}
DWELL=${DWELL:-260}
export DISPLAY=:83
OUT=/work/np64out; mkdir -p "$OUT"
ROOM=TP$(date +%s | tail -c 5)
pkill -9 -f "Xvfb :83" 2>/dev/null; rm -f /tmp/.X83-lock /tmp/.X11-unix/X83
Xvfb :83 -screen 0 1600x700x24 >/dev/null 2>&1 & sleep 2
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None)
port=9281
for n in alice bob; do
  rm -rf "/tmp/tp_$n"; mkdir -p "/tmp/tp_$n"; rm -f "$OUT/tp_$n.log"
  HOME="/tmp/tp_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 \
    NP64_ROOM=$ROOM NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" --setting DebugServer/Enabled=true --setting DebugServer/Port=$port \
    --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/tp_$n.log" 2>&1 &
  port=$((port+1))
  sleep 3
done
echo "== turnpike room $ROOM course $COURSE =="
sleep 20
# force the course on the HOST (joiner adopts via course sync)
python3 /work/gdbpoke.py 9281 $COURSE_ADDR 000000$COURSE
# wait for racing (block-done on bob)
for i in $(seq 1 120); do
  sleep 1
  grep -q "io wW 0020 <- 43" "$OUT/tp_bob.log" 2>/dev/null && { echo "racing at t=$i"; break; }
done
sleep $DWELL
echo "== perf sections (alice, during turnpike race) =="
python3 /work/perfdump.py 9281 2>&1 | grep -vE "^\s+\[sim\] ptcl"
pkill -9 -x ares 2>/dev/null
echo "alice hashes: $(grep -c 'io wW 0020 <- 77' $OUT/tp_alice.log)"
echo "bob   hashes: $(grep -c 'io wW 0020 <- 77' $OUT/tp_bob.log)"
echo "drop-applied pokes: $(grep -hoE 'io wW 0020 <- 58[0-9a-f]{6}' $OUT/tp_*.log | sort -u | head -3 | tr '\n' ' ')"
echo "ROOM=$ROOM"
echo TURNPIKE-DONE
