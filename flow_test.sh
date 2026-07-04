#!/bin/bash
# flow_test.sh — validate: (a) no room membership at boot (host lobby empty
# until the joiner CONFIRMS the code in the JOIN menu), (b) rename still works
# roomless, (c) "JSUPPE VERSION N" build stamp on the title screen.
# Two instances, NP64_ROOM=FLOWT1 prefill only, no NP64_NAME.
set -u
ROM=${ROM:-/work/mk64_flowtest.z64}
export DISPLAY=:77
pkill -9 -x Xvfb 2>/dev/null; rm -f /tmp/.X77-lock /tmp/.X11-unix/X77
Xvfb :77 -screen 0 1400x620x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/ob.log 2>&1 & sleep 1
ARESBIN=/src/build/desktop-ui/ares
for n in a b; do
  rm -rf "/tmp/fl_$n"; mkdir -p "/tmp/fl_$n"
  HOME="/tmp/fl_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6464 NP64_ROOM=FLOWT1 \
    "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
    --setting Input/Driver=None --system "Nintendo 64" "$ROM" >"/tmp/ares_$n.log" 2>&1 &
  sleep 1
done
# catch the title screen (menu 0x0a) on instance a for the version stamp
for i in $(seq 1 300); do
  if grep -q "e000000a" /tmp/ares_a.log 2>/dev/null; then
    scrot -o /work/flow_title.png
    break
  fi
  sleep 0.2
done
sleep 75   # let both walk rename + join
W=0
for WID in $(xdotool search --name mk64 2>/dev/null | sort -u); do
  xdotool windowmove "$WID" $((W * 700)) 0 2>/dev/null
  xdotool windowsize "$WID" 640 580 2>/dev/null
  W=$((W + 1))
done
sleep 2
scrot -o /work/flow_lobby.png
echo "--- identity lines ---"
grep -h "identity" /tmp/ares_a.log /tmp/ares_b.log
pkill -9 -x ares 2>/dev/null
pkill -9 -x Xvfb 2>/dev/null
