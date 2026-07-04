#!/bin/bash
# Two-instance mk64 netplay: np64-relay + two headless ares in one room (DEVROM).
# Runs INSIDE ares-builder with --network host + /dev/dri (GPU) as root.
#   alice = node 0, bob = node 1. Each broadcasts its kart snapshot; the relay
#   forwards to the other, whose slot-1 puppet is driven by it.
set -u
ROM=/work/mk64.us.z64
RELAY=/work/relay-target/release/np64-relay
OUT=/work/np64out
DWELL="${DWELL:-42}"
mkdir -p "$OUT"; rm -f "$OUT"/two_*.png "$OUT"/relay.log "$OUT"/aA.log "$OUT"/aB.log 2>/dev/null

export DISPLAY=:99
Xvfb :99 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1

"$RELAY" --bind 127.0.0.1:6465 --verbose >"$OUT/relay.log" 2>&1 &
RELAYPID=$!
sleep 1

# alice (node 0) with register-I/O trace; bob (node 1) plain.
mkdir -p /tmp/homeA /tmp/homeB
HOME=/tmp/homeA NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 \
  NP64_RELAY=127.0.0.1:6465 NP64_ROOM=DEVROM NP64_NAME=alice \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None \
  --system "Nintendo 64" "$ROM" >"$OUT/aA.log" 2>&1 &
A=$!
sleep 2
HOME=/tmp/homeB NP64_ENABLE=1 NP64_LOG=1 \
  NP64_RELAY=127.0.0.1:6465 NP64_ROOM=DEVROM NP64_NAME=bob \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None \
  --system "Nintendo 64" "$ROM" >"$OUT/aB.log" 2>&1 &
B=$!

cap_windows() {  # $1 = label
  local n=0 W
  for W in $(xdotool search --name "mk64" 2>/dev/null | sort -u); do
    n=$((n+1))
    xdotool windowactivate "$W" 2>/dev/null; sleep 0.4
    scrot -u -o "$OUT/${1}_win${n}.png" 2>/dev/null
  done
}

for i in $(seq 1 "$DWELL"); do
  sleep 1
  for WID in $(xdotool search --class ares 2>/dev/null; xdotool search --name mk64 2>/dev/null); do
    xdotool windowactivate "$WID" 2>/dev/null
    xdotool key --window "$WID" Return 2>/dev/null
  done
  case $i in 30) cap_windows t30 ;; 41) cap_windows t41 ;; esac
done

kill $A $B $RELAYPID 2>/dev/null
sleep 1

echo "===== RELAY LOG ====="; tail -20 "$OUT/relay.log"
echo "===== ALICE NetPak64 lifecycle ====="; grep -E "NetPak64\] (device|power|first|link|session|welcome|join|peer)" "$OUT/aA.log" -i | head -12
echo "===== BOB NetPak64 lifecycle ====="; grep -E "NetPak64\] (device|power|first|link|session|welcome|join|peer)" "$OUT/aB.log" -i | head -12
echo "===== ALICE register I/O: TX + RX counts ====="
echo "TX_DOORBELL(wW 0048): $(grep -c 'io wW 0048' "$OUT/aA.log")"
echo "TX_LEN_DST (wW 0040): $(grep -c 'io wW 0040' "$OUT/aA.log")"
echo "RX_CONSUME (wW 0058): $(grep -c 'io wW 0058' "$OUT/aA.log")"
echo "RX_WIN DMA reads      : $(grep -c 'RX_WIN+' "$OUT/aA.log")"
echo "sample TX_LEN_DST values:"; grep 'io wW 0040' "$OUT/aA.log" | sort | uniq -c | head
echo "sample STATUS values (rW 000c):"; grep 'io rW 000c' "$OUT/aA.log" | awk '{print $NF}' | sort | uniq -c | head
echo "===== SHOTS ====="; ls -la "$OUT"/t30_win*.png "$OUT"/t41_win*.png 2>/dev/null
