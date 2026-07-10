#!/bin/bash
# specpeek.sh — boot a replay, then peek the HUD-gate inputs live.
set -u
DN=93
export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -f "Xvfb :$DN" 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X$DN
Xvfb :$DN -screen 0 1000x800x24 >/dev/null 2>&1 &
sleep 3
rm -rf /tmp/spec; mkdir -p /tmp/spec
HOME=/tmp/spec ARES_ISV=1 NP64_ENABLE=1 NP64_LOG=1 \
  NP64_RELAY=127.0.0.1:6465 NP64_ROOM=SQ$(date +%s | tail -c 5) NP64_NAME=alice \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --setting DebugServer/Enabled=true --setting DebugServer/Port=9168 \
  --system "Nintendo 64" /work/mk64_test.z64 >/tmp/spec.log 2>&1 &
sleep 30
python3 /work/tapeload.py 9168 /work/replay_src.tape || { echo "FAIL"; pkill -9 -x ares; exit 1; }
sleep 45
for k in 1 2 3; do
  # gGamestate(s32) 800dc69c, gIsGamePaused(u16) 800dc834
  python3 /work/gdbpeek.py 9168 800dc69c 800dc834
  sleep 2
done
pkill -9 -x ares 2>/dev/null; pkill -9 -f "Xvfb :$DN" 2>/dev/null
echo PEEK-DONE
