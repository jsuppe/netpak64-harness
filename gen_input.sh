#!/bin/bash
export DISPLAY=:99 HOME=/root
Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 &
sleep 2
openbox >/dev/null 2>&1 &
sleep 1
timeout 7 /src/build/desktop-ui/ares --no-file-prompt >/dev/null 2>&1
sleep 1
f=/root/.local/share/ares/settings.bml
echo "===exists: $(ls -la $f 2>/dev/null | awk '{print $5}') bytes==="
sed -n '77,145p' "$f" 2>/dev/null
# also copy the whole settings out to /work so I can inspect/edit + reuse
cp "$f" /work/ares_settings.bml 2>/dev/null && echo "===copied to /work/ares_settings.bml==="
