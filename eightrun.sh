#!/bin/bash
# eightrun.sh — 8-player full-race + second-race probe (task #35 data).
# Runs 8 instances to race COMPLETION and beyond; periodic screenshots; rich
# per-instance telemetry summary. Usage: eightrun.sh <DISPLAY> <ROOM> <SECS>
set -u
DN=${1:?}; ROOM=${2:?}; SECS=${3:?}
NAMES="alice bob carol dave erin frank grace harry"

export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -x Xvfb 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X${DN}
Xvfb :$DN -screen 0 1340x1250x24 >/dev/null 2>&1 &
sleep 3
[ -S /tmp/.X11-unix/X${DN} ] || { echo "FATAL: no X"; exit 1; }

i=0
for n in $NAMES; do
  rm -rf /tmp/e8_$n; mkdir -p /tmp/e8_$n
  HOME=/tmp/e8_$n NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 \
    NP64_RELAY=127.0.0.1:6464 NP64_ROOM=$ROOM NP64_NAME=$n \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None \
    --system "Nintendo 64" /work/mk64_test.z64 >/tmp/e8_$n.log 2>&1 &
  i=$((i+1))
  sleep 2
done
sleep 8
pgrep -x ares | wc -l | xargs echo "ares instances:"

# tile 8 windows 4x2
WINS=$(xdotool search --name mk64 2>/dev/null | head -8 || true)
i=0
for w in $WINS; do
  xdotool windowmove $w $(( (i%4)*335 )) $(( (i/4)*620 )) 2>/dev/null || true
  i=$((i+1))
done

mkdir -p /work/shots
END=$((SECS / 15))
for k in $(seq -w 1 $END); do
  scrot -z -o /work/shots/e8_$k.png 2>/dev/null || true
  sleep 15
done

pkill -9 -x ares 2>/dev/null
for n in $NAMES; do
  L=/tmp/e8_$n.log
  [ -f $L ] || continue
  # lap|path telemetry: 0x5E llpppp (lap nibble at bits 16-19)
  LAPS=$(grep -o 'io wW 0020 <- 5e......' $L | sed 's/.*5e//' | awk '{print substr($0,1,2)}' | uniq -c | tr '\n' ' ')
  echo "== $n: sim=$(grep -c 'io wW 0020 <- 76' $L) 7D=$(grep -c 'io wW 0020 <- 7d' $L) drops=$(grep -o 'io wW 0020 <- 58......' $L | uniq | tr '\n' ' ')"
  echo "   lap-progress(count lap): $LAPS"
  echo "   last-5E: $(grep -o 'io wW 0020 <- 5e......' $L | tail -1)  state-5F-last: $(grep -o 'io wW 0020 <- 5f......' $L | tail -3 | tr '\n' ' ')"
  cp $L /work/e8_$n.log
done
pkill -9 -x Xvfb 2>/dev/null
echo RUN-DONE
