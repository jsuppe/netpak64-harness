#!/bin/bash
export DISPLAY=:99
pkill -9 -f "desktop-ui/ares" 2>/dev/null; pkill -9 Xvfb 2>/dev/null; pkill -9 openbox 2>/dev/null
sleep 1
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99   # clear stale lock/socket so the new size takes
Xvfb :99 -screen 0 1800x1500x24 >/tmp/xvfb.log 2>&1 &
sleep 2
echo "xdotool getdisplaygeometry: $(xdotool getdisplaygeometry 2>&1)"
echo "--- xdpyinfo dimensions ---"; xdpyinfo 2>/dev/null | grep -iE "dimensions|depth of root" || echo "(no xdpyinfo)"
echo "--- xrandr ---"; xrandr 2>/dev/null | head -4 || echo "(no xrandr)"
echo "--- Xvfb log tail ---"; tail -5 /tmp/xvfb.log
scrot -o /tmp/pg.png 2>/dev/null && python3 -c "import struct;f=open('/tmp/pg.png','rb');f.read(16);import sys;w,h=struct.unpack('>II',f.read(8));print('scrot size:',w,'x',h)"
pkill -9 Xvfb 2>/dev/null
