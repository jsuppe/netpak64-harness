#!/bin/bash
# Solo boot probes: A=green+dev, B=inert+dev, C=inert nodev. Screenshot at 22s.
export DISPLAY=:92
pkill -9 -f "desktop-ui/ares" 2>/dev/null
pkill -f "Xvfb :92" 2>/dev/null
rm -f /tmp/.X92-lock /tmp/.X11-unix/X92
Xvfb :92 -screen 0 700x620x24 >/dev/null 2>&1 &
sleep 2
run_probe() {
  rm -rf /tmp/pr; mkdir -p /tmp/pr
  HOME=/tmp/pr NP64_ENABLE=$2 NP64_LOG=1 NP64_TRACE_IO=1 NP64_RELAY=127.0.0.1:6465 NP64_ROOM=PROBE$3 NP64_NAME=solo \
    /src/build/desktop-ui/ares --no-file-prompt --setting Input/Defocus=Allow --setting Audio/Driver=None \
    --setting Input/Driver=None --system "Nintendo 64" "/work/$1" >"/tmp/probe_$3.log" 2>&1 &
  AP=$!
  sleep 22
  scrot -o "/work/probe_$3.png" 2>/dev/null
  kill -9 "$AP" 2>/dev/null
  sleep 1
  echo "$3: log=$(wc -l < /tmp/probe_$3.log) io=$(grep -c 'io ' /tmp/probe_$3.log)"
}
run_probe mk64_green.z64 1 A_green
run_probe mk64_inert.z64 1 B_inert
run_probe mk64_inert.z64 0 C_nodev
pkill -f "Xvfb :92" 2>/dev/null
exit 0
