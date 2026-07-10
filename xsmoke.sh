#!/bin/bash
# xsmoke.sh — CROSS-MACHINE release smoke test (REQUIRED gate, run on melchior
# host, NOT in the container). alice = headless ares in the local container;
# bob = ares on balthazar over Tailscale (real latency + loss). Loopback
# batteries are BLIND to delivery/timing bugs (v54 lesson) — this is the gate
# that catches them.
#
# PASS = bob emitted sim hashes AND both hash streams identical.
# Usage: bash xsmoke.sh   (assumes staged /mnt/micron/jsuppe/netpak/mk64_test.z64
#                          already scp'd to balthazar:/tmp/mk64_test.z64)
set -u
NP=/mnt/micron/jsuppe/netpak
ROOM=XS$(date +%s | tail -c 5)
ARES_B=/Users/jsuppe/dev/ares/build_macos/desktop-ui/RelWithDebInfo/ares.app/Contents/MacOS/ares
echo "== xsmoke room $ROOM =="
rm -f $NP/np64out/x_alice.log $NP/np64out/x_bob.log

# 0. same ROM on both sides (md5 gate — mixed builds desync by layout alone)
scp -q $NP/mk64_test.z64 balthazar:/tmp/mk64_test.z64 || { echo "XSMOKE-FAIL (scp)"; exit 1; }

# 1. alice in the container (background)
docker run --rm --network host -v /home/melchior/dev/ares:/src -v $NP:/work ares-builder:latest bash -c "
export DISPLAY=:81
pkill -9 -f 'Xvfb :81' 2>/dev/null; rm -f /tmp/.X81-lock /tmp/.X11-unix/X81
Xvfb :81 -screen 0 800x700x24 >/dev/null 2>&1 & sleep 2
rm -rf /tmp/xalice; mkdir -p /tmp/xalice
HOME=/tmp/xalice NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=$ROOM NP64_NAME=alice \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system 'Nintendo 64' /work/mk64_test.z64 > /work/np64out/x_alice.log 2>&1 &
sleep 300
pkill -9 -x ares" &
ALICE_JOB=$!

# 2. wait until alice owns node 0 (join poke 5b000000); ghost seats otherwise
for i in $(seq 1 30); do
  sleep 3
  grep -q "5b000000" $NP/np64out/x_alice.log 2>/dev/null && break
done
grep -q "5b000000" $NP/np64out/x_alice.log 2>/dev/null || { echo "XSMOKE-FAIL (alice not node 0)"; exit 1; }
echo "alice is node 0"

# 3. bob on balthazar (retry ssh up to 3x — macOS sleeps)
BOB_OK=0
for try in 1 2 3; do
  if timeout 20 ssh -o ConnectTimeout=8 -o BatchMode=yes balthazar \
    "pkill -f 'ares.*mk64_test' 2>/dev/null; rm -rf /tmp/np64_bobtest; mkdir -p /tmp/np64_bobtest; \
     HOME=/tmp/np64_bobtest NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=100.96.183.93:6465 \
     NP64_ROOM=$ROOM NP64_NAME=bob nohup $ARES_B --system 'Nintendo 64' /tmp/mk64_test.z64 \
     > /tmp/ares_bobtest.log 2>&1 & sleep 2; pgrep -f 'ares.*mk64_test' | head -1"; then
    BOB_OK=1; break
  fi
  sleep 5
done
[ "$BOB_OK" = 1 ] || { echo "XSMOKE-FAIL (bob launch — balthazar unreachable?)"; exit 1; }
echo "bob launched"

# 4. let the race run (alice self-starts ~150 autopilot steps in)
wait $ALICE_JOB 2>/dev/null
timeout 20 ssh -o BatchMode=yes balthazar "pkill -f 'ares.*mk64_test' 2>/dev/null; true"
scp -q balthazar:/tmp/ares_bobtest.log $NP/np64out/x_bob.log || { echo "XSMOKE-FAIL (bob log)"; exit 1; }

# 5. verdict: bob must have raced AND streams must be identical
BOBH=$(grep -c "io wW 0020 <- 77" $NP/np64out/x_bob.log || true)
echo "bob hashes: $BOBH"
[ "${BOBH:-0}" -gt 100 ] || { echo "XSMOKE-FAIL (bob never raced — entry wedge?)"; exit 1; }
docker run --rm -v /home/melchior/dev/ares:/src -v $NP:/work ares-builder:latest \
  python3 /work/decode_det4.py /work/np64out/x_alice.log /work/np64out/x_bob.log | tail -2
docker run --rm -v /home/melchior/dev/ares:/src -v $NP:/work ares-builder:latest \
  python3 /work/decode_det4.py /work/np64out/x_alice.log /work/np64out/x_bob.log | grep -q "IDENTICAL" \
  && echo "XSMOKE-PASS (room $ROOM)" || echo "XSMOKE-FAIL (hash divergence)"
