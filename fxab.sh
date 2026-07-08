#!/bin/bash
# fxab.sh — offline attract-demo screenshot for effects A/B (v44-overlay probe).
# Usage: fxab.sh <rom-in-/work> <label>. Boots the ROM STOCK (no NP64) and
# screenshots the attract demo race, where rocket-start smoke / drift effects
# are obvious. Demo starts ~35s after boot on the title screen.
ROM=$1; LABEL=$2
export DISPLAY=:96
pkill -9 -f "desktop-ui/ares" 2>/dev/null
rm -f /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :96 -screen 0 700x620x24 >/dev/null 2>&1 &
sleep 2
rm -rf /tmp/fx; mkdir -p /tmp/fx
HOME=/tmp/fx /src/build/desktop-ui/ares --no-file-prompt \
  --setting Input/Defocus=Allow --setting Audio/Driver=None \
  --setting Input/Driver=None --system "Nintendo 64" "/work/$ROM" >/tmp/fx.log 2>&1 &
AP=$!
sleep 90
scrot -o "/work/fx_${LABEL}_a.png"
sleep 30
scrot -o "/work/fx_${LABEL}_b.png"
sleep 30
scrot -o "/work/fx_${LABEL}_c.png"
kill -9 $AP 2>/dev/null
exit 0
