#!/bin/bash
# Two-instance NetPak64 mk64 demo for balthazar (native macOS ares).
# Boots two ares windows running the modded ROM, joined to one relay room.
# Usage:  bash balthazar_run.sh
set -u

MELCHIOR="${MELCHIOR:-100.96.183.93}"          # melchior over Tailscale (or 192.168.1.154 on LAN)
ROM="${ROM:-$HOME/mk64_net.z64}"
ROOM="${ROOM:-MK64BAL}"

echo "== pulling modded ROM from melchior =="
scp "jsuppe@${MELCHIOR}:/home/jsuppe/dev/mk64/build/us/mk64.us.z64" "$ROM" || {
  echo "scp failed. Set MELCHIOR=<ip> or copy the ROM to $ROM manually."; exit 1; }

echo "== locating ares (netpak fork) + relay on balthazar =="
ARES="$(find "$HOME/dev/ares" -maxdepth 6 -type f -name ares -path '*Contents/MacOS/*' 2>/dev/null | head -1)"
[ -z "$ARES" ] && ARES="$(find "$HOME/dev/ares" -maxdepth 6 -type d -name 'ares.app' 2>/dev/null | head -1)/Contents/MacOS/ares"
RELAY="$(find "$HOME/dev/np64-relay" -maxdepth 4 -type f -name np64-relay 2>/dev/null | head -1)"
echo "  ares : $ARES"
echo "  relay: $RELAY"
[ -x "$ARES" ]  || { echo "ares binary not found — set ARES=/path/to/ares"; exit 1; }
[ -x "$RELAY" ] || { echo "np64-relay not found — build it in ~/dev/np64-relay (cargo build --release) or set RELAY="; exit 1; }

echo "== starting relay on 127.0.0.1:6464 =="
"$RELAY" --dev >/tmp/np64-relay.log 2>&1 &
RELAYPID=$!
sleep 1

launch() {  # $1=name  $2=home
  mkdir -p "$2"
  HOME="$2" NP64_ENABLE=1 NP64_LOG=1 \
    NP64_RELAY=127.0.0.1:6464 NP64_ROOM="$ROOM" NP64_NAME="$1" \
    "$ARES" --system "Nintendo 64" "$ROM" >"/tmp/ares_$1.log" 2>&1 &
  echo $!
}

echo "== launching two ares windows (alice, bob) in room $ROOM =="
A=$(launch alice /tmp/np64_home_alice)
sleep 3
B=$(launch bob   /tmp/np64_home_bob)

echo ""
echo "Two ares windows should now be open. Both auto-start into Mario Raceway"
echo "and join relay room '$ROOM'. Watch /tmp/np64-relay.log for both peers:"
echo "   tail -f /tmp/np64-relay.log"
echo ""
echo "PIDs: alice=$A bob=$B relay=$RELAYPID   (kill with: kill $A $B $RELAYPID)"
