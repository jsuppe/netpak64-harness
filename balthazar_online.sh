#!/bin/bash
# Native ONLINE two-player test for balthazar (macOS ares, netpak fork).
#
# Boots TWO ares windows that talk to the relay running on melchior. Nothing is
# auto-driven: YOU drive the menus. One window HOSTs, the other JOINs by code.
#
# Usage:   bash balthazar_online.sh
#   env overrides: MELCHIOR=<ip>  ROM=<path>  ARES=<path>  RELAYPORT=6465
set -u

MELCHIOR="${MELCHIOR:-100.96.183.93}"      # melchior over Tailscale (or 192.168.1.154 on LAN)
RELAYPORT="${RELAYPORT:-6465}"
ROM="${ROM:-$HOME/mk64_net.z64}"
CODE="${CODE:-}"                           # shared 6-char room code; both windows pre-fill it
                                           # (empty = old behavior: HOST creates a random code)
WINDOWS="${WINDOWS:-2}"                    # 1 = just the host window (racing melchior bots)

# Ghost cleanup: windows from previous runs stay CONNECTED in the same room,
# eat the 8 seats, and wedge the start handshake (the relay only reaps them
# ~30s after they die). Kill any earlier instances before launching new ones.
echo "== closing game windows from previous runs =="
pkill -f "mk64_net.z64" 2>/dev/null && sleep 2 || true

echo "== pulling HUMAN LOCKSTEP ROM from melchior (expect md5 5f5f9dbf...) =="
scp "jsuppe@${MELCHIOR}:/mnt/micron/jsuppe/netpak/mk64_netpak_human.z64" "$ROM" || {
  echo "scp failed. Set MELCHIOR=<ip> or copy the ROM to $ROM manually."; exit 1; }
md5 "$ROM" 2>/dev/null || md5sum "$ROM" 2>/dev/null

echo "== locating ares (netpak fork) =="
ARES="${ARES:-}"
if [ -z "$ARES" ]; then
  # known build location first, then a deeper search (the binary is ~7 dirs down)
  ARES="$HOME/dev/ares/build_macos/desktop-ui/RelWithDebInfo/ares.app/Contents/MacOS/ares"
  [ -f "$ARES" ] || ARES="$(find "$HOME/dev/ares" -maxdepth 9 -type f -name ares -path '*.app/Contents/MacOS/*' 2>/dev/null | head -1)"
fi
echo "  ares : $ARES"
[ -f "$ARES" ] || { echo "ares binary not found — set ARES=/full/path/to/ares.app/Contents/MacOS/ares"; exit 1; }

# --- ARES STALENESS CHECK (2026-07-10: the Jul-4 build silently lacked the
# FIND GAME device commands — rooms were created private no matter what was
# picked). Compares the netpak device sources here against melchior's
# CANONICAL tree, and the local binary's age against the local sources.
# Warns loudly; set SKIP_STALE_CHECK=1 to bypass, REBUILD=1 to auto-rebuild.
echo "== ares staleness check =="
LOCAL_HASH=$(cat "$HOME/dev/ares/thirdparty/netpak-core/src/"*.cpp \
                 "$HOME/dev/ares/ares/n64/netpak/"*.cpp 2>/dev/null | md5 -q 2>/dev/null)
CANON_HASH=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "jsuppe@${MELCHIOR}" \
  "docker run --rm -v /home/melchior/dev/ares:/src ares-builder:latest \
   sh -c 'cat /src/thirdparty/netpak-core/src/*.cpp /src/ares/n64/netpak/*.cpp 2>/dev/null | md5sum' 2>/dev/null" \
  2>/dev/null | awk '{print $1}')
if [ -z "${SKIP_STALE_CHECK:-}" ] && [ -n "$CANON_HASH" ] && [ -n "$LOCAL_HASH" ]; then
  if [ "$LOCAL_HASH" != "$CANON_HASH" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! ARES SOURCE IS STALE vs melchior's canonical netpak tree  !!"
    echo "!! Online features may silently misbehave (this exact class  !!"
    echo "!! made FIND GAME 'broken' on Jul 10). Ask Claude to sync,   !!"
    echo "!! or run with SKIP_STALE_CHECK=1 to play anyway.            !!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    [ -z "${REBUILD:-}" ] && exit 1
  else
    echo "  netpak sources match canonical ($LOCAL_HASH)"
  fi
fi
# binary older than its own sources = forgot to rebuild
ARES_BIN_DEFAULT="$HOME/dev/ares/build_macos/desktop-ui/RelWithDebInfo/ares.app/Contents/MacOS/ares"
if [ -f "$ARES_BIN_DEFAULT" ]; then
  NEWEST_SRC=$(find "$HOME/dev/ares/thirdparty/netpak-core/src" "$HOME/dev/ares/ares/n64/netpak" \
               -name '*.cpp' -newer "$ARES_BIN_DEFAULT" 2>/dev/null | head -1)
  if [ -n "$NEWEST_SRC" ] || [ -n "${REBUILD:-}" ]; then
    [ -n "$NEWEST_SRC" ] && echo "  BINARY OLDER THAN SOURCE ($NEWEST_SRC) — rebuilding..."
    /opt/homebrew/bin/cmake --build "$HOME/dev/ares/build_macos" --config RelWithDebInfo -j8 \
      || { echo "rebuild FAILED — see output above"; exit 1; }
    echo "  rebuild done"
  else
    echo "  binary up to date ($(stat -f '%Sm' "$ARES_BIN_DEFAULT"))"
  fi
fi

echo "== using melchior's relay at ${MELCHIOR}:${RELAYPORT} (no local relay needed) =="

launch() {  # $1=label (log name)  $2=home
  mkdir -p "$2"
  # NP64_ROOM=CODE pre-fills the in-game join code (both windows share it); empty
  # leaves the menu to create/enter a code manually.
  # NP64_NAME is deliberately NOT set: the name you pick in-game (ONLINE ->
  # NAME) persists per-window in $2/.netpak64_name and is used from then on.
  # First run defaults to "player" — set your name once in the menu.
  HOME="$2" NP64_ENABLE=1 NP64_LOG=1 \
    NP64_RELAY="${MELCHIOR}:${RELAYPORT}" NP64_ROOM="$CODE" \
    "$ARES" --setting Input/Defocus=Block --system "Nintendo 64" "$ROM" >"/tmp/ares_$1.log" 2>&1 &
  echo $!
}

[ -n "$CODE" ] && echo "== shared room code: $CODE (pre-filled in both windows) =="

echo "== launching ares (host=alice$( [ "$WINDOWS" -ge 2 ] && echo ", join=bob" )) =="
A=$(launch alice /tmp/np64_home_alice)
B=""
if [ "$WINDOWS" -ge 2 ]; then
  sleep 3
  B=$(launch bob /tmp/np64_home_bob)
fi

cat <<EOF

Two ares windows are open. If keyboard input isn't mapped, set it once per
window in  Settings > Inputs > Nintendo 64 > Controller Port 1  (D-Pad, A, B,
Start, L, R). Then:

  WINDOW 1 (alice) = HOST
    Title: press Start/A to enter the menus
    Main menu: go to MODE SELECT, choose ONLINE
    ONLINE screen: HOST GAME (A)  ->  the ROOM CODE (shared code if CODE= was set)
    In the lobby: L / R to pick the COURSE, then press START to begin

  WINDOW 2 (bob) = JOIN
    Same path to the ONLINE screen, choose JOIN GAME (A)
    The code-entry screen always appears: with CODE= set it is pre-filled
    (just press A); otherwise dial the code and press A.
    NEW in v9: whoever confirms a fresh code FIRST becomes the HOST (course
    picker + START) — so with CODE= set you can simply pick JOIN in both
    windows; the first one gets the host lobby, the second waits as a guest.

  When alice presses START, BOTH pick a character; the map screen shows
  "WAITING FOR ALL PLAYERS" until everyone is in, then the race starts in
  LOCKSTEP: one shared simulation — same items, same collisions, same
  standings on both screens.

  LOCKSTEP NOTES (new engine):
   - If a window briefly FREEZES, it is waiting for the other player's input
     (network hiccup) — it resumes by itself.
   - If a player quits/crashes mid-race, after ~5s their kart becomes a CPU
     bot and the race continues. This includes the HOST.
   - If the host quits before the race starts, joiners return to the online
     menu after ~3s.

  TIP: run with a shared code so neither window types anything:
       CODE=RACE23 bash balthazar_online.sh

Per-instance logs:  /tmp/ares_alice.log   /tmp/ares_bob.log
  (look for "relay=${MELCHIOR}:${RELAYPORT}" and "LINK" / "room" lines)

PIDs: alice=$A bob=$B   (kill both: kill $A $B)

If the windows can't reach the relay, check UDP ${RELAYPORT} to ${MELCHIOR} is
open over Tailscale, or re-run with the LAN ip:  MELCHIOR=192.168.1.154 bash balthazar_online.sh
EOF
