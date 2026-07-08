#!/bin/bash
# bridge_start.sh — (re)start the np64 SC64 bridge daemon.
# In a file so pkill patterns can't match the invoking shell (harness note).
cd /mnt/micron/jsuppe/netpak
for p in $(pgrep -f "np64_bridge.py"); do kill -9 "$p" 2>/dev/null; done
sleep 1

# The FTDI re-enumerates (ttyUSB0 -> ttyUSB1 -> ...) after any USB hiccup;
# always take the first present device instead of hardcoding ttyUSB0.
DEV=$(ls /dev/ttyUSB* 2>/dev/null | head -1)
if [ -z "$DEV" ]; then
  echo "BRIDGE FAILED: no /dev/ttyUSB* device (SC64 not on USB)"
  exit 1
fi
BASE=$(basename "$DEV")

# Permissions reset on every re-enumeration (root:dialout).
[ -w "$DEV" ] || docker run --rm -v /dev:/hostdev busybox chmod 666 "/hostdev/$BASE"

# FTDI latency timer: default 16 ms buffers every serial packet in the cart's
# USB chip. 1 ms cuts ~15 ms/leg off lockstep traffic. Resets on replug, so
# (re)apply on every bridge start. Root-owned file -> docker.
if [ "$(cat /sys/bus/usb-serial/devices/$BASE/latency_timer 2>/dev/null)" != "1" ]; then
  docker run --rm --privileged -v /sys:/sys busybox \
    sh -c "echo 1 > /sys/bus/usb-serial/devices/$BASE/latency_timer" 2>/dev/null
  echo "latency_timer($BASE) -> $(cat /sys/bus/usb-serial/devices/$BASE/latency_timer)"
fi

nohup python3 -u np64_bridge.py --dev "$DEV" --name console --room "${1:-BENCHX}" \
  > bridge_v43.log 2>&1 &
sleep 3
echo "--- bridge_v43.log ($DEV) ---"
tail -5 bridge_v43.log
pgrep -f "np64_bridge.py" >/dev/null && echo "BRIDGE RUNNING (pid $(pgrep -f np64_bridge.py))" || echo "BRIDGE FAILED"
