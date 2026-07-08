#!/bin/bash
# fxvideo.sh — record OFFLINE 1P GP (determinism autopilot) to show kart
# effects (exhaust/boost/skid) are intact in the current build.
# Output: /work/fx_effects.mp4
export DISPLAY=:98
pkill -9 -x ares 2>/dev/null
rm -f /tmp/.X98-lock /tmp/.X11-unix/X98
Xvfb :98 -screen 0 700x620x24 >/dev/null 2>&1 &
sleep 2
rm -rf /tmp/fxv; mkdir -p /tmp/fxv
HOME=/tmp/fxv NP64_ENABLE=1 NP64_LOG=1 NP64_RELAY=loopback \
  /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64_dtfx.z64 >/tmp/fxv.log 2>&1 &
AP=$!
sleep 6
ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size 700x620 -i :98 \
  -t 85 -vf "crop=650:480:34:58" -c:v libx264 -preset veryfast -crf 26 \
  -pix_fmt yuv420p /work/fx_effects.mp4
kill -9 $AP 2>/dev/null
exit 0
