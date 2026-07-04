#!/bin/bash
# GPU-accelerated + register-I/O trace. Runs inside ares-builder with /dev/dri
# passed through so parallel-RDP uses hardware Vulkan (lavapipe was ~50x slower).
set -u
export DISPLAY=:99
OUT=/work/np64out
mkdir -p "$OUT"; rm -f "$OUT"/trace_*.png "$OUT"/ares_trace.log 2>/dev/null

Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1

# NP64_TRACE_IO=1 makes the glue log device register reads/writes (budget-capped).
NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 /src/build/desktop-ui/ares \
  --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 >"$OUT/ares_trace.log" 2>&1 &
ARES=$!

for i in $(seq 1 48); do
  sleep 1
  WID=$(xdotool search --name ares 2>/dev/null | head -1)
  if [ -n "$WID" ]; then
    xdotool windowactivate "$WID" 2>/dev/null
    xdotool key --window "$WID" Return 2>/dev/null
  fi
  case $i in 20|35|47) scrot -o "$OUT/trace_${i}s.png" 2>/dev/null ;; esac
done

kill $ARES 2>/dev/null
sleep 1
echo "===RENDERER==="; grep -iE "vulkan|opengl|gpu|device.*name|llvmpipe|radeon|intel" "$OUT/ares_trace.log" | head
echo "===NP64 DEVICE LINES==="; grep -iE "NetPak64" "$OUT/ares_trace.log" | head -8
echo "===REGISTER I/O TRACE (first 40)==="; grep -iE "TRACE|IO |read|write|doorbell|MAGIC|VERSION|STATUS|TX|RX|CMD|DOM2|0x05f0" "$OUT/ares_trace.log" | grep -iE "np64|netpak|0x05f0|doorbell|MAGIC|dom2|TX_|RX_" | head -40
echo "===TX/RX/DOORBELL counts==="
for k in doorbell DOORBELL TX_BUF RX_WIN RX_CONSUME MAGIC VERSION DOM2 CMD_DATA; do printf "%s: %s\n" "$k" "$(grep -c "$k" "$OUT/ares_trace.log" 2>/dev/null)"; done
echo "===SHOTS==="; ls -la "$OUT"/trace_*.png 2>/dev/null
