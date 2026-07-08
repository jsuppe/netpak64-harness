#!/bin/bash
# dtfx.sh — solo OFFLINE GP (determinism-test autopilot), screenshot burst
# around the race start to check kart effects (exhaust/boost/skid smoke).
# Usage: dtfx.sh <rom-in-/work> <label>
ROM=$1; LABEL=$2
export DISPLAY=:97
pkill -9 -x ares 2>/dev/null
rm -f /tmp/.X97-lock /tmp/.X11-unix/X97
Xvfb :97 -screen 0 700x620x24 >/dev/null 2>&1 &
sleep 2
rm -rf /tmp/dt; mkdir -p /tmp/dt
HOME=/tmp/dt NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=loopback \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" "/work/$ROM" >/tmp/dt.log 2>&1 &
AP=$!
sleep 30
for k in 1 2 3 4 5 6 7 8 9; do
  scrot -o "/work/dt_${LABEL}_$k.png"
  sleep 4
done
kill -9 $AP 2>/dev/null
exit 0
