#!/bin/bash
# Runs inside the ares-builder container. Mounts:
#   /src  = melchior ~/dev/ares  (the built netpak-fork ares)
#   /work = /mnt/micron/jsuppe/netpak (ROM + output, shared)
set -u
export DISPLAY=:99
# Force software Vulkan (lavapipe) + software GL — the container has no GPU
# access, so ares' parallel-RDP must run on CPU.
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
OUT=/work/np64out
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/ares.log 2>/dev/null

Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1

NP64_ENABLE=1 NP64_LOG=1 /src/build/desktop-ui/ares \
  --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 >"$OUT/ares.log" 2>&1 &
ARES=$!

# Dismiss the startup modal + keep focus so emulation advances; screenshot along
# the way. Boot+auto-start into the race takes ~5s, so shots at 10/18/26/34s
# should land mid-race.
for i in $(seq 1 40); do
  sleep 1
  WID=$(xdotool search --name ares 2>/dev/null | head -1)
  if [ -n "$WID" ]; then
    xdotool windowactivate "$WID" 2>/dev/null
    xdotool key --window "$WID" Return 2>/dev/null
  fi
  case $i in 10|18|26|34) scrot -o "$OUT/shot_${i}s.png" 2>/dev/null ;; esac
done

kill $ARES 2>/dev/null
sleep 1
echo "===ARES_LOG_TAIL==="
tail -60 "$OUT/ares.log"
echo "===NP64_COUNT==="
grep -icE "NP64|NetPak" "$OUT/ares.log"
echo "===NP64_LINES==="
grep -iE "NP64|NetPak|probe|detect" "$OUT/ares.log" | head -60
echo "===SHOTS==="
ls -la "$OUT"/*.png 2>/dev/null
