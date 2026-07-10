#!/bin/bash
# relay_deploy.sh — restart the canonical relay (np64-relay-gh build) on :6465.
# In a file so pkill/kill patterns can't match the invoking shell.
BIN=/mnt/micron/jsuppe/repos/np64-relay-gh/target/release/np64-relay
for p in $(pgrep -f "np64-relay --bind 0.0.0.0:6465"); do kill -9 "$p" 2>/dev/null; done
sleep 1
cd /mnt/micron/jsuppe/repos/np64-relay-gh
nohup "$BIN" --bind 0.0.0.0:6465 --verbose --diag-dir /mnt/micron/jsuppe/netpak/diag > /mnt/micron/jsuppe/netpak/relay6465.log 2>&1 &
sleep 2
ss -ulnp 2>/dev/null | grep -q ":6465" && echo "RELAY RUNNING on :6465 (pid $(pgrep -f 'np64-relay --bind 0.0.0.0:6465' | head -1))" || echo "RELAY FAILED"
