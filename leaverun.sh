#!/bin/bash
# leaverun.sh — lobby-leaver repro: carol joins the room, gets killed BEFORE the
# race starts; alice+bob must still get a running lockstep race (ghost seat ->
# never-played DROP -> CPU from frame 0). Usage: leaverun.sh <DISPLAY> <ROOM> <SECS>
set -u
DN=${1:?}; ROOM=${2:?}; SECS=${3:?}

export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -x Xvfb 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X${DN}
Xvfb :$DN -screen 0 1400x620x24 >/dev/null 2>&1 &
sleep 3
[ -S /tmp/.X11-unix/X${DN} ] || { echo "FATAL: no X"; exit 1; }

for n in alice bob carol; do
  rm -rf /tmp/lv_$n; mkdir -p /tmp/lv_$n
  HOME=/tmp/lv_$n NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 \
    NP64_RELAY=127.0.0.1:6464 NP64_ROOM=$ROOM NP64_NAME=$n \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None \
    --system "Nintendo 64" /work/mk64_test.z64 >/tmp/lv_$n.log 2>&1 &
  echo $! > /tmp/lv_$n.pid
  sleep 3
done

sleep 30   # everyone in the lobby by now; alice's self-start comes later
kill -9 $(cat /tmp/lv_carol.pid) 2>/dev/null
echo "carol killed at t=+30s (in lobby)"

sleep $SECS
pkill -9 -x ares 2>/dev/null
for n in alice bob; do
  L=/tmp/lv_$n.log
  echo "== $n: sim=$(grep -c 'io wW 0020 <- 76' $L) 7D=$(grep -c 'io wW 0020 <- 7d' $L) drop58=$(grep -o 'io wW 0020 <- 58......' $L | uniq | tr '\n' ' ') lastSim=$(grep -o 'io wW 0020 <- 76......' $L | tail -1)"
  cp $L /work/lv_$n.log
done
pkill -9 -x Xvfb 2>/dev/null
echo RUN-DONE
