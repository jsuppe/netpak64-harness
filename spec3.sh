#!/bin/bash
# spec3.sh — live-spectator harness (inside ares-builder container).
# alice (node 0, racer, self-starts), bob (racer), wanda (SPECTATOR via Z+A).
# Verifies: all 3 sim-hash streams identical; wanda contributes no inputs;
# spec roster poke (0x5A) shows mask with wanda's bit on every instance.
set -u
export DISPLAY=:78
OUT=/work/np64out; mkdir -p "$OUT"
NAMES=(alice bob wanda)
ROOM=SW$(date +%s | tail -c 5) # NOT $$: bash -c in docker is always pid 1 -> ghost seats
for n in "${NAMES[@]}"; do rm -f "$OUT/s3_$n.log"; done
pkill -9 -f "Xvfb :78" 2>/dev/null; rm -f /tmp/.X78-lock /tmp/.X11-unix/X78
Xvfb :78 -screen 0 2400x700x24 >/dev/null 2>&1 & sleep 2

pkill -f "np64-relay --bind 127.0.0.1:6465" 2>/dev/null
if ! (ss -ulnp 2>/dev/null | grep -q ":6465 "); then
  /work/relay-target/release/np64-relay --bind 127.0.0.1:6465 --verbose >"$OUT/s3_relay.log" 2>&1 &
fi
sleep 1
ARESBIN=/src/build/desktop-ui/ares
COMMON=(--no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None --setting Input/Driver=None --system "Nintendo 64")

PIDS=()
for n in "${NAMES[@]}"; do
  mkdir -p "/tmp/s3_$n"
  HOME="/tmp/s3_$n" NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=$ROOM NP64_NAME="$n" \
    "$ARESBIN" "${COMMON[@]}" /work/mk64_test.z64 >"$OUT/s3_$n.log" 2>&1 &
  PIDS+=($!)
  sleep 2
done

for i in $(seq 1 "${DWELL:-150}"); do
  sleep 1
  if [ "$i" = "${SHOT1:-90}" ] || [ "$i" = "${SHOT2:-120}" ]; then
    mapfile -t WINS < <(xdotool search --name mk64 2>/dev/null | sort -u)
    k=0
    for W in "${WINS[@]}"; do
      xdotool windowmove "$W" $(( k * 790 )) 10 2>/dev/null
      k=$((k+1))
    done
    sleep 1
    scrot -o "$OUT/s3_i${i}.png" 2>/dev/null
  fi
done
for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
sleep 1

echo "===== spec roster (0x5A mask|localbit) per instance ====="
for n in "${NAMES[@]}"; do
  echo "$n: $(grep -oiE 'io wW 0020 <- 5a[0-9a-f]{6}' "$OUT/s3_$n.log" | tail -1)"
done
echo "===== wanda input silence (LS_TAG sends appear as ch0 tx in her log) ====="
echo "alice 0x77 hashes: $(grep -c 'io wW 0020 <- 77' "$OUT/s3_alice.log")"
echo "bob   0x77 hashes: $(grep -c 'io wW 0020 <- 77' "$OUT/s3_bob.log")"
echo "wanda 0x77 hashes: $(grep -c 'io wW 0020 <- 77' "$OUT/s3_wanda.log")"
echo "===== 3-way hash identity ====="
python3 /work/decode_det4.py "$OUT/s3_alice.log" "$OUT/s3_bob.log" "$OUT/s3_wanda.log"
echo SPEC3-DONE
