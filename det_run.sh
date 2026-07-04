#!/bin/bash
# Determinism probe: two ares instances run the IDENTICAL offline GP race, driven
# only by the in-ROM deterministic navigator + autodrive (no xdotool, no network).
# Each emits (frame, state-hash) every race frame; compare the streams by frame.
set -u
export DISPLAY=:99
OUT=/work/np64out; mkdir -p "$OUT"; rm -f "$OUT"/det_a.log "$OUT"/det_b.log
Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2
openbox >/tmp/openbox.log 2>&1 & sleep 1
ARESBIN=/src/build/desktop-ui/ares
mkdir -p /tmp/hA /tmp/hB
# NP64 enabled only for the poke channel; no relay pairing, and the determinism
# build skips all tx/rx anyway, so the two sims are fully independent.
for tag in A B; do
  home=/tmp/h$tag
  HOME=$home NP64_ENABLE=1 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6464 NP64_NAME=det$tag \
    "$ARESBIN" --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
    --setting Input/Driver=None --system "Nintendo 64" /work/mk64_test.z64 \
    >"$OUT/det_$(echo $tag | tr A-Z a-z).log" 2>&1 &
done
sleep "${DWELL:-75}"
pkill -f "$ARESBIN" 2>/dev/null; sleep 1
echo "hashes  A=$(grep -c 'io wW 0020 <- 77' "$OUT/det_a.log")  B=$(grep -c 'io wW 0020 <- 77' "$OUT/det_b.log")"
python3 /work/decode_det.py "$OUT/det_a.log" "$OUT/det_b.log"
