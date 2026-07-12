#!/bin/bash
# battleprobe.sh — force online BATTLE on Big Donut, 2 instances, observe.
set -u
BATTLE_ADDR=${BATTLE_ADDR:-80417bd0}
export DISPLAY=:88
OUT=/work/np64out; mkdir -p "$OUT"
ROOM=BT$(date +%s | tail -c 5)
pkill -9 -f "Xvfb :88" 2>/dev/null; rm -f /tmp/.X88-lock /tmp/.X11-unix/X88
Xvfb :88 -screen 0 1400x560x24 >/dev/null 2>&1 & sleep 2
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None)
port=9341
for n in alice bob; do
  rm -rf "/tmp/bt_$n"; mkdir -p "/tmp/bt_$n"; rm -f "$OUT/bt_$n.log"
  HOME="/tmp/bt_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=$ROOM NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" --setting DebugServer/Enabled=true --setting DebugServer/Port=$port \
    --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/bt_$n.log" 2>&1 &
  port=$((port+1)); sleep 3
done
echo "== battleprobe room $ROOM =="
# poke battle mode on BOTH before they start (repeat during menu nav)
for t in 8 14 20 26 32; do
  sleep 6
  python3 /work/gdbpoke.py 9341 $BATTLE_ADDR 00000001 >/dev/null 2>&1
  python3 /work/gdbpoke.py 9342 $BATTLE_ADDR 00000001 >/dev/null 2>&1
done
# wait for racing
for i in $(seq 1 90); do sleep 1; grep -q "io wW 0020 <- 43" "$OUT/bt_bob.log" 2>/dev/null && { echo "entered race t=$i"; break; }; done
sleep 40
mapfile -t W < <(xdotool search --name mk64 2>/dev/null | sort -u)
k=0; for w in "${W[@]}"; do xdotool windowmove "$w" $((k*690)) 10 2>/dev/null; k=$((k+1)); done
sleep 1
scrot -o /work/np64out/battle_probe.png 2>/dev/null
pkill -9 -x ares 2>/dev/null
echo "alice hashes: $(grep -c 'io wW 0020 <- 77' $OUT/bt_alice.log)"
echo "bob   hashes: $(grep -c 'io wW 0020 <- 77' $OUT/bt_bob.log)"
echo "ROOM=$ROOM"
echo BATTLEPROBE-DONE
