#!/bin/bash
# tapetest.sh — run a standard preset-room pair with the GDB stub on alice,
# race for a while, then dump alice's input tape (tapedump.py) and stop.
set -u
DN=90
export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -x Xvfb 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X${DN}
Xvfb :$DN -screen 0 1400x620x24 >/dev/null 2>&1 &
sleep 3
for n in alice bob; do
  EXTRA=""
  [ "$n" = alice ] && EXTRA="--setting DebugServer/Enabled=true --setting DebugServer/Port=9166"
  rm -rf /tmp/tt_$n; mkdir -p /tmp/tt_$n
  HOME=/tmp/tt_$n NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 \
    NP64_RELAY=127.0.0.1:6465 NP64_ROOM=TAPE01 NP64_NAME=$n \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None $EXTRA \
    --system "Nintendo 64" /work/mk64_test.z64 >/tmp/tt_$n.log 2>&1 &
  sleep 3
done
sleep "${1:-130}"
python3 /work/tapedump.py 9166 /work/race.tape
pkill -9 -x ares 2>/dev/null
for n in alice bob; do
  L=/tmp/tt_$n.log
  echo "== $n: sim=$(grep -c 'io wW 0020 <- 76' $L) 7D=$(grep -c 'io wW 0020 <- 7d' $L)"
done
pkill -9 -x Xvfb 2>/dev/null
echo TAPE-DONE
