#!/bin/bash
# pauseshot.sh — 2 instances race, poke bob's pause overlay open, screenshot.
set -u
export DISPLAY=:87
OUT=/work/np64out; mkdir -p "$OUT"
ROOM=PS$(date +%s | tail -c 5)
pkill -9 -f "Xvfb :87" 2>/dev/null; rm -f /tmp/.X87-lock /tmp/.X11-unix/X87
Xvfb :87 -screen 0 1400x560x24 >/dev/null 2>&1 & sleep 2
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None)
port=9331
for n in alice bob; do
  rm -rf "/tmp/ps_$n"; mkdir -p "/tmp/ps_$n"
  HOME="/tmp/ps_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=$ROOM NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" --setting DebugServer/Enabled=true --setting DebugServer/Port=$port \
    --system "Nintendo 64" /work/mk64_test.z64 >"/tmp/ps_$n.log" 2>&1 &
  port=$((port+1)); sleep 3
done
# wait for racing
for i in $(seq 1 120); do sleep 1; grep -q "io wW 0020 <- 43" "/tmp/ps_bob.log" 2>/dev/null && break; done
sleep 8
# open bob's pause overlay and keep it open (long hold, no quit)
python3 /work/gdbpoke.py 9332 80417bc4 00007fff 80417bc0 00000010 >/dev/null 2>&1
sleep 4
mapfile -t W < <(xdotool search --name mk64 2>/dev/null | sort -u)
k=0; for w in "${W[@]}"; do xdotool windowmove "$w" $((k*690)) 10 2>/dev/null; k=$((k+1)); done
sleep 1
scrot -o /work/np64out/pause_overlay.png 2>/dev/null
pkill -9 -x ares 2>/dev/null
echo PAUSESHOT-DONE
