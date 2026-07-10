#!/bin/bash
# spectest.sh — visual test for SPECTATOR mode (inside ares-builder container).
# Boots a solo replay WITH video, then GDB-pokes the spectator knobs
# (gNetSpecView / gNetSpecKart) and screenshots each view with scrot.
# Prereq: /work/replay_src.tape recorded on the STAGED mk64_test.z64.
# Addresses from build/us/mk64.us.map — MUST match the staged ROM:
SPEC_KART=${SPEC_KART:-8041b9c8}
SPEC_VIEW=${SPEC_VIEW:-8041b9c9}
set -u
DN=93
export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -f "Xvfb :$DN" 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X$DN
Xvfb :$DN -screen 0 1000x800x24 >/dev/null 2>&1 &
sleep 3
[ -S /tmp/.X11-unix/X$DN ] || { echo "FATAL: no Xvfb"; exit 1; }

rm -rf /tmp/spec; mkdir -p /tmp/spec /work/shots
HOME=/tmp/spec ARES_ISV=1 NP64_ENABLE=1 NP64_LOG=1 \
  NP64_RELAY=127.0.0.1:6465 NP64_ROOM=SP$(printf %04d $(($$ % 10000))) NP64_NAME=alice \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --setting DebugServer/Enabled=true --setting DebugServer/Port=9168 \
  --system "Nintendo 64" /work/mk64_test.z64 >/tmp/spec.log 2>&1 &
sleep 30
python3 /work/tapeload.py 9168 /work/replay_src.tape || { echo "FAIL (load)"; pkill -9 -x ares; exit 1; }
sleep 45   # menus -> race start -> a bit of racing

scrot -z -o /work/shots/spec_0chase_k0.png
# front view, kart 0
python3 /work/gdbpoke.py 9168 $SPEC_VIEW 02
sleep 4; scrot -z -o /work/shots/spec_1front_k0.png
# lakitu rear, kart 0
python3 /work/gdbpoke.py 9168 $SPEC_VIEW 01
sleep 4; scrot -z -o /work/shots/spec_2lakitu_k0.png
# cinematic, kart 0
python3 /work/gdbpoke.py 9168 $SPEC_VIEW 03
sleep 6; scrot -z -o /work/shots/spec_3cine_k0.png
# chase, kart 3
python3 /work/gdbpoke.py 9168 $SPEC_VIEW 00 $SPEC_KART 03
sleep 4; scrot -z -o /work/shots/spec_4chase_k3.png
# front, kart 5
python3 /work/gdbpoke.py 9168 $SPEC_VIEW 02 $SPEC_KART 05
sleep 4; scrot -z -o /work/shots/spec_5front_k5.png
# lakitu, kart 7
python3 /work/gdbpoke.py 9168 $SPEC_VIEW 01 $SPEC_KART 07
sleep 4; scrot -z -o /work/shots/spec_6lakitu_k7.png

grep -iE "REPLAY-START|REPLAY-END|netpak: rep" /tmp/spec.log | tail -4
pkill -9 -x ares 2>/dev/null; pkill -9 -f "Xvfb :$DN" 2>/dev/null
echo SPECTEST-DONE
