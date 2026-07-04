#!/bin/bash
# Launch N headless AI racers on melchior that JOIN a human's room.
#
# The human (e.g. balthazar) HOSTS with a room code FIRST — creating the room
# makes the human node 0, so the bots (test-ROM joiners) wait for the human's
# START, auto-pick characters, hit the ready barrier, and then waypoint-AI
# drive the race. Run on the melchior host:
#
#     CODE=RACE23 BOTS=7 ./bots.sh
#
#   CODE   room code the human is hosting (A-Z + 2-9 only)     [required]
#   BOTS   number of AI racers, 1-7                            [default 3]
#   RELAY  relay address                                       [default 127.0.0.1:6464]
#   DWELL  seconds to keep them alive                          [default 600]
#
# NOTE: bots run mk64_test.z64 (lockstep + menu/autodrive automation). Its SIM
# is identical to the human build — the automation flags only change local
# input generation — so mixed human+bot lockstep stays deterministic.
# Pacing: lockstep runs at the SLOWEST participant; 7 bots on one box can pull
# the shared race below 60fps — use BOTS=3 for a smoother human experience.
set -u
CODE="${CODE:?set CODE=<room code the human is hosting>}"
BOTS="${BOTS:-3}"
RELAY="${RELAY:-127.0.0.1:6464}"
DWELL="${DWELL:-600}"
NAMES=(bot1 bot2 bot3 bot4 bot5 bot6 bot7)

docker rm -f npbots >/dev/null 2>&1
docker run -d --rm --name npbots --network host \
  --device /dev/dri/renderD128 --device /dev/dri/card1 \
  -v /home/melchior/dev/ares:/src -v /mnt/micron/jsuppe/netpak:/work \
  ares-builder:latest sleep $((DWELL + 120)) >/dev/null
sleep 2

docker exec -e CODE="$CODE" -e BOTS="$BOTS" -e RELAY="$RELAY" -e DWELL="$DWELL" npbots bash -c '
export DISPLAY=:78
pkill -9 -x Xvfb 2>/dev/null; rm -f /tmp/.X78-lock /tmp/.X11-unix/X78
Xvfb :78 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/ob.log 2>&1 & sleep 1
ARESBIN=/src/build/desktop-ui/ares
NAMES=(bot1 bot2 bot3 bot4 bot5 bot6 bot7)
for i in $(seq 0 $((BOTS - 1))); do
  n=${NAMES[$i]}
  mkdir -p "/tmp/hb_$n"
  HOME="/tmp/hb_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY="$RELAY" NP64_ROOM="$CODE" NP64_NAME="$n" \
    "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
    --setting Input/Driver=None --system "Nintendo 64" /work/mk64_test.z64 >"/tmp/ares_$n.log" 2>&1 &
  sleep 2
done
echo "$BOTS bots joining room $CODE via $RELAY — alive for ${DWELL}s"
for t in $(seq 1 "$DWELL"); do
  sleep 1
  for WID in $(xdotool search --name mk64 2>/dev/null | sort -u); do
    xdotool key --window "$WID" Return 2>/dev/null
  done
done'
docker rm -f npbots >/dev/null 2>&1
