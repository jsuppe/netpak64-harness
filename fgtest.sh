#!/bin/bash
# fgtest.sh — FIND GAME end-to-end in ares: carol hosts a PUBLIC game (class ->
# visibility -> create), alice browses FIND GAME and joins the listing, race
# launches. NO NP64_ROOM (that env selects the preset-join autopilot).
# Screenshots every 5 s to /work/shots_fg; log tails printed at the end.
set -u
DN=91
export DISPLAY=:$DN
pkill -9 -x ares 2>/dev/null; pkill -9 -x Xvfb 2>/dev/null; sleep 1
rm -f /tmp/.X${DN}-lock /tmp/.X11-unix/X${DN}
Xvfb :$DN -screen 0 1400x620x24 >/dev/null 2>&1 &
sleep 3

for n in carol alice; do
  rm -rf /tmp/fg_$n; mkdir -p /tmp/fg_$n
  HOME=/tmp/fg_$n NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 \
    NP64_RELAY=127.0.0.1:6465 NP64_NAME=$n \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None \
    --system "Nintendo 64" /work/mk64_test.z64 >/tmp/fg_$n.log 2>&1 &
  sleep 6   # carol first: her room must exist before alice's first LIST
done
sleep 4
pgrep -x ares >/dev/null || { echo "FATAL: ares died"; tail -5 /tmp/fg_carol.log; exit 1; }

WINS=$(xdotool search --name mk64 2>/dev/null | head -2 || true)
i=0; for w in $WINS; do xdotool windowmove $w $((i*660)) 20 2>/dev/null || true; i=$((i+1)); done

rm -rf /work/shots_fg; mkdir -p /work/shots_fg
for k in $(seq -w 1 24); do
  scrot -z -o /work/shots_fg/fg$k.png 2>/dev/null || true
  sleep 3
done

pkill -9 -x ares 2>/dev/null
for n in carol alice; do
  L=/tmp/fg_$n.log
  echo "== $n: pokes=$(grep -c 'io wW 0020' $L) sim=$(grep -c 'io wW 0020 <- 76' $L) 7D=$(grep -c 'io wW 0020 <- 7d' $L)"
  cp $L /work/fg_$n.log
done
pkill -9 -x Xvfb 2>/dev/null
echo FG-DONE
