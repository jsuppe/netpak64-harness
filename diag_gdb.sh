#!/bin/bash
set -u
export DISPLAY=:99
Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 &
sleep 2
openbox >/tmp/openbox.log 2>&1 &
sleep 1
echo "=== gdb backtrace of the crash (12s timeout) ==="
NP64_ENABLE=1 NP64_LOG=1 timeout 20 gdb -q -batch \
  -ex "run" \
  -ex "echo \n==== BACKTRACE (crashing thread) ====\n" \
  -ex "bt" \
  -ex "echo \n==== ALL THREADS ====\n" \
  -ex "thread apply all bt" \
  --args /src/build/desktop-ui/ares \
    --no-file-prompt --setting Input/Defocus=Allow \
    --setting Audio/Driver=None --setting Input/Driver=None \
    --system "Nintendo 64" /work/mk64.us.z64 2>&1 | grep -vE "^\[Thread|^\[New Thread|Missing separate debuginfo" | head -80
