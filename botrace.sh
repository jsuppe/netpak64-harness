#!/bin/bash
# botrace.sh — 2-driver race, report each bot's rank over time + item usage.
# Verifies the autopilot drives representatively (mid-pack, uses items) rather
# than wall-grinding in 7th/8th. COURSE=<hex> forces a track.
set -u
COURSE=${COURSE:-08}          # default Luigi Raceway
COURSE_ADDR=${COURSE_ADDR:-80417b74}
DWELL=${DWELL:-240}
export DISPLAY=:85
OUT=/work/np64out; mkdir -p "$OUT"
ROOM=BR$(date +%s | tail -c 5)
pkill -9 -f "Xvfb :85" 2>/dev/null; rm -f /tmp/.X85-lock /tmp/.X11-unix/X85
Xvfb :85 -screen 0 1600x700x24 >/dev/null 2>&1 & sleep 2
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None)
port=9301
for n in alice bob; do
  rm -rf "/tmp/br_$n"; mkdir -p "/tmp/br_$n"; rm -f "$OUT/br_$n.log"
  HOME="/tmp/br_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 \
    NP64_ROOM=$ROOM NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" --setting DebugServer/Enabled=true --setting DebugServer/Port=$port \
    --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/br_$n.log" 2>&1 &
  port=$((port+1))
  sleep 3
done
echo "== botrace room $ROOM course 0x$COURSE =="
sleep 20
[ "$COURSE" != "ff" ] && python3 /work/gdbpoke.py 9301 $COURSE_ADDR 000000$COURSE >/dev/null 2>&1
for i in $(seq 1 120); do sleep 1; grep -q "io wW 0020 <- 43" "$OUT/br_bob.log" 2>/dev/null && { echo "racing t=$i"; break; }; done
sleep $DWELL
pkill -9 -x ares 2>/dev/null
# 0x5D poke = [me<<16 | rank<<8 | item]; alice=slot0, bob=slot1
echo "== alice (slot 0) rank/item timeline (rank, item) =="
grep -oE 'io wW 0020 <- 5d00[0-9a-f]{4}' "$OUT/br_alice.log" | sed 's/.*5d00//' | \
  awk '{r=strtonum("0x" substr($0,1,2)); it=strtonum("0x" substr($0,3,2)); print "rank="r" item="it}' | uniq -c | tail -12
echo "== items fired (Z presses in applied input) =="
echo "  alice progress (0x5E lap|path): $(grep -oE 'io wW 0020 <- 5e[0-9a-f]{6}' $OUT/br_alice.log | tail -1)"
echo "ROOM=$ROOM"
echo BOTRACE-DONE
