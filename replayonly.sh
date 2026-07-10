#!/bin/bash
# replayonly.sh — phase 2 of replaytest.sh alone: replay /work/replay_src.tape
# on a fresh solo instance and report the verdict + forensics.
set -u
DN=91
export DISPLAY=:$DN
DWELL_REP=${DWELL_REP:-400}
pkill -9 -x ares 2>/dev/null; pkill -9 -f "Xvfb :$DN" 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X$DN
Xvfb :$DN -screen 0 1400x620x24 >/dev/null 2>&1 &
sleep 3
rm -rf /tmp/rt_rep; mkdir -p /tmp/rt_rep
HOME=/tmp/rt_rep ARES_ISV=1 NP64_ENABLE=1 NP64_LOG=1 \
  NP64_RELAY=127.0.0.1:6465 NP64_ROOM=RP$(date +%s | tail -c 5) NP64_NAME=alice \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None --setting Video/Driver=None \
  --setting DebugServer/Enabled=true --setting DebugServer/Port=9167 \
  --system "Nintendo 64" /work/mk64_test.z64 >/tmp/rt_rep.log 2>&1 &
sleep 30
python3 /work/tapeload.py 9167 /work/replay_src.tape || { echo "FAIL (load)"; pkill -9 -x ares; exit 1; }
for i in $(seq 1 $((DWELL_REP / 10))); do
  sleep 10
  V=$(python3 /work/gdbpeek.py 9167 80440024 80440028 8044002c 2>/dev/null | awk "{print \$2}" | tr "\n" " ")
  # gdbpeek can transiently return nothing (stub busy); with set -u a bare
  # `set --` then makes $1 fatal. Substitute placeholders and keep polling.
  set -- ${V:-PEEKFAIL 0 0}
  echo "t=$((i*10))s verdict=$1 checked=$2 bad=$3"
  if [ "$1" = "444F4E45" ] || [ "$1" = "444f4e45" ]; then break; fi
done
echo "== perf =="
python3 /work/perfdump.py 9167 2>&1
echo "== forensics =="
python3 /work/fpdiff.py 9167 2>&1
pkill -9 -x ares 2>/dev/null
echo REPLAYONLY-DONE
