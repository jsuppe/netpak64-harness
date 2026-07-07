#!/bin/bash
# Launch the staged test ROM solo with the ares GDB server on :9123.
export DISPLAY=:93
X93=$(pgrep -x Xvfb | while read p; do grep -lz ":93" /proc/$p/cmdline 2>/dev/null && echo $p; done | grep -o "^[0-9]*$" | head -1)
[ -n "$X93" ] && kill -9 $X93 2>/dev/null
rm -f /tmp/.X93-lock /tmp/.X11-unix/X93
Xvfb :93 -screen 0 700x620x24 >/dev/null 2>&1 &
sleep 2
rm -rf /tmp/gw; mkdir -p /tmp/gw
HOME=/tmp/gw NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=WEDGEGDB NP64_NAME=solo \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
  --setting Input/Driver=None --setting DebugServer/Enabled=true --setting DebugServer/Port=9123 \
  --system "Nintendo 64" /work/mk64_test.z64 >/tmp/wedge.log 2>&1 &
echo "ares pid $!"
