#!/bin/bash
# Single instance connected to melchior's relay (so session commands work),
# with NP64_TRACE_IO. The ROM's menu auto-navigator selects ONLINE -> HOST.
set -u
export DISPLAY=:99
OUT=/work/np64out
mkdir -p "$OUT"; rm -f "$OUT"/on_*.png "$OUT"/ares_online.log

Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1

# NP64_RELAY set, NP64_ROOM unset -> device connects (LINK_UP) but the menu
# drives session_create/join.
NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6464 \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 >"$OUT/ares_online.log" 2>&1 &
ARES=$!

for i in $(seq 1 50); do
  sleep 1
  WID=$(xdotool search --name ares 2>/dev/null | head -1)
  if [ -n "$WID" ]; then
    xdotool windowactivate "$WID" 2>/dev/null
    xdotool key --window "$WID" Return 2>/dev/null
  fi
  case $i in 25|38|48) scrot -o "$OUT/on_${i}s.png" 2>/dev/null ;; esac
done

kill $ARES 2>/dev/null; sleep 1
echo "===RENDERER==="; grep -iE "vulkan|opengl|stalled" "$OUT/ares_online.log" | head -3
echo "===NP64==="; grep -iE "NetPak64|relay|room|joined|session|create|welcome" "$OUT/ares_online.log" | head -15
echo "===menu nav pokes (e0=screen, f0=online step)==="; grep "io wW 0020" "$OUT/ares_online.log" | awk '{print $NF}' | grep -E "^e0|^f0|^ff" | uniq | head -20
echo "===SHOTS==="; ls -la "$OUT"/on_*.png 2>/dev/null
