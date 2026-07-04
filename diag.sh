#!/bin/bash
set -u
export DISPLAY=:99
Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1
echo "=== vulkan info ==="
command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>&1 | grep -iE "deviceName|driverName|apiVersion|GPU id" | head
echo "VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-<unset>}"
ls /usr/share/vulkan/icd.d/ 2>/dev/null
echo "=== ares --help settings (Video) ==="
/src/build/desktop-ui/ares --help 2>&1 | grep -iE "video|driver|vulkan|setting" | head
echo "=== launch ares foreground (timeout 12s) ==="
NP64_ENABLE=1 NP64_LOG=1 timeout 12 stdbuf -oL -eL /src/build/desktop-ui/ares \
  --no-file-prompt --setting Input/Defocus=Allow \
  --setting Audio/Driver=None --setting Input/Driver=None \
  --system "Nintendo 64" /work/mk64.us.z64 2>&1 | head -60
echo "=== exit: $? ==="
