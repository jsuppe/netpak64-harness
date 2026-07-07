#!/bin/bash
# eyerun.sh — canonical 2-instance harness run INSIDE the ares-builder container.
# Handles every pitfall hit so far: stale X locks, dead Xvfb, silent ares death,
# stale room seats, screenshot capture via scrot.
# Usage: eyerun.sh <DISPLAYNUM> <ROOM> <RACE_SECONDS> [SHOTS_EVERY_SECONDS]
set -u
DN=${1:?displaynum}; ROOM=${2:?room}; SECS=${3:?seconds}; SHOT=${4:-0}

export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -x Xvfb 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X${DN}
for try in 1 2 3; do
  Xvfb :$DN -screen 0 1400x620x24 >/dev/null 2>&1 &
  sleep 3
  [ -S /tmp/.X11-unix/X${DN} ] && break
  pkill -9 -x Xvfb 2>/dev/null; rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X${DN}; sleep 1
done
[ -S /tmp/.X11-unix/X${DN} ] || { echo "FATAL: Xvfb :$DN not up after 3 tries"; exit 1; }

for n in alice bob; do
  rm -rf /tmp/er_$n; mkdir -p /tmp/er_$n
  HOME=/tmp/er_$n NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 \
    NP64_RELAY=127.0.0.1:6465 NP64_ROOM=$ROOM NP64_NAME=$n \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None \
    --system "Nintendo 64" /work/mk64_test.z64 >/tmp/er_$n.log 2>&1 &
  sleep 3
done
sleep 5
pgrep -x ares >/dev/null || { echo "FATAL: ares died at launch"; tail -5 /tmp/er_alice.log; exit 1; }

# side-by-side for screenshots
WINS=$(xdotool search --name mk64 2>/dev/null | head -2 || true)
i=0; for w in $WINS; do xdotool windowmove $w $((i*660)) 20 2>/dev/null || true; i=$((i+1)); done

mkdir -p /work/shots
if [ "$SHOT" -gt 0 ]; then
  END=$((SECS / SHOT))
  for k in $(seq -w 1 $END); do
    scrot -z -o /work/shots/f$k.png 2>/dev/null || true
    sleep $SHOT
  done
else
  sleep $SECS
fi

pkill -9 -x ares 2>/dev/null
for n in alice bob; do
  L=/tmp/er_$n.log
  echo "== $n: alive-log=$(wc -l <$L) pokes=$(grep -c 'io wW 0020' $L) sim=$(grep -c 'io wW 0020 <- 76' $L) 7D=$(grep -c 'io wW 0020 <- 7d' $L)"
  echo "   colcnt-last16: $(grep -o 'io wW 0020 <- e.......' $L | tail -16 | sed 's/io wW 0020 <- //' | tr '\n' ' ')"
  echo "   DF-tail: $(grep -o 'io wW 0020 <- df......' $L | tail -2 | sed 's/io wW 0020 <- //' | tr '\n' ' ')"
  cp $L /work/er_$n.log
done
pkill -9 -x Xvfb 2>/dev/null
echo RUN-DONE
