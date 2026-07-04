#!/bin/bash
# Two instances that pair THROUGH THE ONLINE MENU: each auto-navigates
# ONLINE -> JOIN -> confirm the default code, so both land in one relay room
# (join-or-create). Uses an isolated relay on 6465 for a clean log.
set -u
RELAY=/work/relay-target/release/np64-relay
OUT=/work/np64out
DWELL="${DWELL:-58}"
mkdir -p "$OUT"; rm -f "$OUT"/tw_*.png "$OUT"/relay.log "$OUT"/aA.log "$OUT"/aB.log

export DISPLAY=:99
Xvfb :99 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1

"$RELAY" --bind 127.0.0.1:6465 --verbose >"$OUT/relay.log" 2>&1 &
sleep 1

ARESBIN=/src/build/desktop-ui/ares
mkdir -p /tmp/hA /tmp/hB
# NP64_ROOM intentionally unset — the menu drives session_join.
HOME=/tmp/hA NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_NAME=alice \
  "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 >"$OUT/aA.log" 2>&1 &
A=$!
sleep 2
HOME=/tmp/hB NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=127.0.0.1:6465 NP64_NAME=bob \
  "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 >"$OUT/aB.log" 2>&1 &
B=$!

for i in $(seq 1 "$DWELL"); do
  sleep 1
  for WID in $(xdotool search --class ares 2>/dev/null; xdotool search --name mk64 2>/dev/null); do
    xdotool windowactivate "$WID" 2>/dev/null; xdotool key --window "$WID" Return 2>/dev/null
  done
  if [ "$i" = 50 ]; then
    n=0
    for W in $(xdotool search --name mk64 2>/dev/null | sort -u); do
      n=$((n+1)); xdotool windowactivate "$W" 2>/dev/null; sleep 0.4; scrot -u -o "$OUT/tw_win${n}.png" 2>/dev/null
    done
  fi
done

kill $A $B 2>/dev/null; pkill -f "np64-relay" 2>/dev/null; sleep 1
echo "===== RELAY LOG (who joined which room) ====="; cat "$OUT/relay.log"
echo "===== SHOTS ====="; ls -la "$OUT"/tw_win*.png 2>/dev/null
