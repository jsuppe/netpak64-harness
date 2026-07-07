#!/bin/bash
# Solo run of the staged test ROM; screenshots at 45s (ONLINE screen, in room
# via NP64_ROOM autopilot) and 60s (lobby if the autopilot advanced).
export DISPLAY=:95
pkill -9 -f "desktop-ui/ares" 2>/dev/null
rm -f /tmp/.X95-lock /tmp/.X11-unix/X95
Xvfb :95 -screen 0 700x620x24 >/dev/null 2>&1 &
sleep 2
rm -rf /tmp/is; mkdir -p /tmp/is
HOME=/tmp/is NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=ICONSHOT NP64_NAME=alice \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
  --setting Input/Driver=None --system "Nintendo 64" /work/mk64_test.z64 >/tmp/is.log 2>&1 &
AP=$!
sleep 45
scrot -o /work/icon_online.png
sleep 15
scrot -o /work/icon_lobby.png
kill -9 $AP 2>/dev/null
exit 0
