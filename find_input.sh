#!/bin/bash
export DISPLAY=:99 HOME=/root
Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 &
sleep 2
openbox >/dev/null 2>&1 &
sleep 1
timeout 6 /src/build/desktop-ui/ares --no-file-prompt >/dev/null 2>&1
echo "===SETTINGS FILES==="
find /root /tmp -name "*.bml" 2>/dev/null
f=$(find /root /tmp -name settings.bml 2>/dev/null | head -1)
echo "===FILE: $f==="
echo "===INPUT / N64 SECTION==="
grep -niE "input|nintendo|controller|gamepad|virtualpad|hotkey" "$f" 2>/dev/null | head -50
echo "===RAW tail of settings (structure) ==="
sed -n '1,60p' "$f" 2>/dev/null
