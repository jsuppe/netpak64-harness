#!/bin/bash
set -u
export DISPLAY=:99
OUT=/work/np64out; mkdir -p "$OUT"; rm -f "$OUT"/boot.png "$OUT"/boot.log
Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1
NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6464 \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 >"$OUT/boot.log" 2>&1 &
A=$!
for i in $(seq 1 16); do sleep 1; done
scrot -o "$OUT/boot.png" 2>/dev/null
kill $A 2>/dev/null; sleep 1
echo "=== driver init / detect ==="; grep -iE "NetPak64|detect|LINK|version" "$OUT/boot.log" | head -6
echo "=== menu-nav pokes (E0.. => auto-nav ON; expect 0) ==="; grep -c "io wW 0020" "$OUT/boot.log"
echo "=== shot ==="; ls -la "$OUT/boot.png"
