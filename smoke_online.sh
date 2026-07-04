#!/bin/bash
set -u
export DISPLAY=:99
OUT=/work/np64out; mkdir -p "$OUT"; rm -f "$OUT"/smoke_*.png "$OUT"/smoke.log
Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1
# relay on 0.0.0.0:6464 already running on the host; --network host reaches it at 127.0.0.1
ARES_ISV=1 NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6464 NP64_NAME=smoke \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/smoke.log" 2>&1 &
A=$!
for i in $(seq 1 95); do
  sleep 1
  WID=$(xdotool search --name mk64 2>/dev/null | head -1)
  [ -n "$WID" ] && { xdotool windowactivate "$WID" 2>/dev/null; xdotool key --window "$WID" Return 2>/dev/null; }
  case $i in 75) scrot -o "$OUT/smoke_40.png" 2>/dev/null ;; 90) scrot -o "$OUT/smoke_52.png" 2>/dev/null ;; esac
done
kill $A 2>/dev/null; sleep 1
echo "=== gamestate / course pokes ==="; grep -c "io wW 0048" "$OUT/smoke.log"
echo "=== reached RACING? (nonzero TX doorbell => in-race net loop running) ==="
echo "TX doorbell frames: $(grep -c 'io wW 0048' "$OUT/smoke.log")"
echo "=== shots ==="; ls -la "$OUT"/smoke_*.png 2>/dev/null
