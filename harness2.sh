#!/bin/bash
# Two-instance repro harness: both instances run mk64_test.z64, auto-navigate
# ONLINE -> JOIN "AAAAAA" -> self-START, so they pair in one relay room and race
# together headlessly. Screenshots each so we can see the camera/puppet behavior.
set -u
export DISPLAY=:99
OUT=/work/np64out; mkdir -p "$OUT"; rm -f "$OUT"/t2_*.png "$OUT"/relay2.log "$OUT"/a2.log "$OUT"/b2.log
Xvfb :99 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1

# Private relay on 6465 for a clean log.
/work/relay-target/release/np64-relay --bind 127.0.0.1:6465 --verbose >"$OUT/relay2.log" 2>&1 &
sleep 1
ARESBIN=/src/build/desktop-ui/ares
mkdir -p /tmp/hA /tmp/hB

ARES_ISV=1 HOME=/tmp/hA NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=TESTAB NP64_NAME=alice \
  "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/a2.log" 2>&1 &
A=$!
sleep "${DELAY:-2}"
HOME=/tmp/hB NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=TESTAB NP64_NAME=bob \
  "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/b2.log" 2>&1 &
B=$!

for i in $(seq 1 "${DWELL:-95}"); do
  sleep 1
  for WID in $(xdotool search --name mk64 2>/dev/null | sort -u); do
    xdotool windowactivate "$WID" 2>/dev/null; xdotool key --window "$WID" Return 2>/dev/null
  done
  if [ "$i" = "${SHOT1:-70}" ] || [ "$i" = "${SHOT2:-88}" ]; then
    n=0
    for W in $(xdotool search --name mk64 2>/dev/null | sort -u); do
      n=$((n+1)); xdotool windowactivate "$W" 2>/dev/null; sleep 0.4
      scrot -o "$OUT/t2_win${n}_i${i}.png" 2>/dev/null
    done
  fi
done
kill $A $B 2>/dev/null; pkill -f "np64-relay" 2>/dev/null; sleep 1

echo "===== RELAY (who paired) ====="; grep -iE "moved to room|node" "$OUT/relay2.log" | tail -6
echo "===== alice in-race state (last 6) ====="; python3 /work/decode_npdbg.py "$OUT/a2.log" 2>/dev/null | grep -E "DRIVABLE|puppet" | tail -6
echo "alice net_race_frame ticks (0x56): $(grep -c 'io wW 0020 <- 56' "$OUT/a2.log")  puppet-count samples (0x56 low byte !=00): $(grep 'io wW 0020 <- 56' "$OUT/a2.log" | awk '{print $NF}' | grep -vE '00$' | wc -l)"
echo "===== SHOTS ====="; ls -la "$OUT"/t2_*.png 2>/dev/null
