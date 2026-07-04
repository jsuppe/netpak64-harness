#!/bin/bash
# NetPak64 debug harness: boots the test ROM headless (menu auto-navigator ->
# online HOST race), captures a burst of screenshots across the race, and dumps
# a readable state timeline decoded from the ROM's tagged NPDBG pokes.
#
#   Build first:  make NON_MATCHING=1 && cp build/us/mk64.us.z64 <share>/mk64_test.z64
#   Run (in the ares-builder container, --network host, DRI devices mounted):
#     bash /work/harness.sh
set -u
export DISPLAY=:99
OUT=/work/np64out; mkdir -p "$OUT"; rm -f "$OUT"/h_*.png "$OUT"/harness.log
Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1

# ARES_ISV mirrors ISViewer to stdout (latent); NP64_TRACE_IO logs the poke
# channel that the decoder reads.
ARES_ISV=1 NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6464 NP64_NAME=harness \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64_test.z64 >"$OUT/harness.log" 2>&1 &
A=$!

# Drive Start each second (menus), and snapshot a burst once the race is up.
for i in $(seq 1 "${DWELL:-150}"); do
  sleep 1
  WID=$(xdotool search --name mk64 2>/dev/null | head -1)
  [ -n "$WID" ] && { xdotool windowactivate "$WID" 2>/dev/null; xdotool key --window "$WID" Return 2>/dev/null; }
  case $i in 60|80|100|120|140|148) scrot -o "$OUT/h_${i}.png" 2>/dev/null ;; esac
done
kill $A 2>/dev/null; sleep 1

echo "================= NPDBG state timeline ================="
python3 /work/decode_npdbg.py "$OUT/harness.log" | tail -60
echo "================= screenshots ================="
ls -la "$OUT"/h_*.png 2>/dev/null
echo "(raw poke channel: grep 'io wW 0020' $OUT/harness.log)"
