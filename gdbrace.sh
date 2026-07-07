#!/bin/bash
# Two-instance race (alice=host, bob=joiner) with the ares GDB stub enabled on
# both: alice :9124, bob :9125. Autopilot drives to a race; camprobe.py then
# samples game state from both instances. Room derives from $1 (default CAMPR).
ROOM=${1:-CAMPR}
export DISPLAY=:96
pkill -9 -f "desktop-ui/ares" 2>/dev/null
rm -f /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :96 -screen 0 1380x620x24 >/dev/null 2>&1 &
sleep 2
launch() { # $1=name $2=gdbport
  local H=/tmp/gr_$1
  rm -rf $H; mkdir -p $H
  HOME=$H NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=$ROOM NP64_NAME=$1 \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None \
    --setting DebugServer/Enabled=true --setting DebugServer/Port=$2 \
    --system "Nintendo 64" /work/mk64_test.z64 >/tmp/gr_$1.log 2>&1 &
}
launch alice 9124
sleep 4
launch bob 9125
echo "launched; race should be underway in ~90s"
exit 0
