#!/bin/bash
# name_test.sh — validate in-game player rename end-to-end.
# Two instances, NO NP64_NAME, fresh HOMEs: both boot as "player"; the
# NET_MENU_TEST autopilot walks the NAME editor (player -> QLAYER), saves,
# then joins the shared room. Pass = each lobby roster shows the OTHER
# instance as QLAYER (a name that exists nowhere in any env/config), the
# relay logs two renames, and ~/.netpak64_name persists QLAYER.
set -u
ROM=${ROM:-/work/mk64_name_test.z64}
export DISPLAY=:77
pkill -9 -x Xvfb 2>/dev/null; rm -f /tmp/.X77-lock /tmp/.X11-unix/X77
Xvfb :77 -screen 0 1400x620x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/ob.log 2>&1 & sleep 1
ARESBIN=/src/build/desktop-ui/ares
for n in a b; do
  rm -rf "/tmp/nh_$n"; mkdir -p "/tmp/nh_$n"
  HOME="/tmp/nh_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=127.0.0.1:6464 NP64_ROOM=NAMET1 \
    "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
    --setting Input/Driver=None --system "Nintendo 64" "$ROM" >"/tmp/ares_$n.log" 2>&1 &
  sleep 3
done
echo "instances up; waiting ${DWELL:-90}s for autopilot rename + lobby"
sleep "${DWELL:-90}"
W=0
for WID in $(xdotool search --name mk64 2>/dev/null | sort -u); do
  xdotool windowmove "$WID" $((W * 700)) 0 2>/dev/null
  xdotool windowsize "$WID" 640 580 2>/dev/null
  W=$((W + 1))
done
sleep 2
scrot -o /work/name_test.png
echo "--- identity lines (ares logs) ---"
grep -h "identity" /tmp/ares_a.log /tmp/ares_b.log
echo "--- persisted files ---"
for n in a b; do echo -n "nh_$n: "; cat "/tmp/nh_$n/.netpak64_name" 2>/dev/null || echo "(none)"; echo; done
pkill -9 -x ares 2>/dev/null
pkill -9 -x Xvfb 2>/dev/null
