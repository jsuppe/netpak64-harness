# Human lockstep build — on-device test kit (balthazar)

## What this is
First build where HUMANS play the lockstep online engine (one shared
deterministic simulation; all prior testing was robot-driven).
ROM: `mk64_netpak_human.z64` (md5 7dac0f6a, JSUPPE VERSION 41 on the title screen) — lockstep ON, all test
automation OFF, real host/join flow.

## New in VERSION 41
- **Joiner camera fixed**: the joiner's chase camera had been re-seeded every
  frame from smoothing state computed for the HOST's kart, so it mirrored the
  host's steering and banking. It now keeps its own state — turning and
  banking on a joiner should look like the host's own view does.
- **Relay status is now an icon**: the text line is gone; a small signal-bars
  meter sits in the top-right of every online screen. Red blinking bar =
  connecting to relay, two green bars = relay connected, three = in a room.

## New in VERSION 40
- **Adaptive input delay**: the host sizes the lockstep input delay from the
  worst lobby ping (2 frames on LAN, up to 8 on slow links) and every console
  adopts the same value at START. Slower connections no longer drag the whole
  race speed down; they cost button-to-action latency instead. Check the lobby
  ping numbers: the delay is roughly 1 + ping/2 frames.
- **Boot landmine fixed for good**: the console boot only loads the first 1MB
  of the game; our grown code had pushed the audio tables past that line,
  which is what caused the "frozen on a menu, black joiner" wedges. The ROM
  now loads its own tail at power-on.

## New: set your player name in-game
ONLINE -> NAME opens a letter editor (stick up/down cycles letters,
left/right moves, A saves, B cancels). The name shows in every lobby
roster, updates live for players already in the room, and persists per
window (`$HOME/.netpak64_name`, so alice/bob windows each keep their own).
The launcher no longer passes NP64_NAME — first boot shows "player" until
you set a name once.

## One-time: update ares on balthazar
The ROM needs the CURRENT NetPak64 device (name registers + SETNAME relay
forwarding — an older ares will save the name locally but nobody else
will see it).
On balthazar:
    cd ~/dev/ares
    git remote add private https://github.com/jsuppe/ares-netpak64.git  # once
    git fetch private && git checkout netpak && git merge private/netpak
    # rebuild the macOS app as usual
(Repo is private under the jsuppe account — needs your GitHub auth on balthazar.)

## Run
    CODE=RACE23 bash balthazar_online.sh
Two windows open (alice=HOST, bob=JOIN, code pre-filled). Or run one window
per machine on the LAN and give a friend the code. Room codes: letters
A-Z + digits 2-9 only (no 0/1).

## What to watch for (this is a TEST of record)
- Do both screens agree on positions/standings the whole race? (lockstep
  guarantee — any visible disagreement is a bug, note the lap/time)
- Items: shells/bananas/lightning must affect both screens identically.
- Brief freezes = waiting for the peer's input (normal on hiccups).
- Quit one window mid-race: the other should continue with that kart as a
  CPU bot after ~5s. Works for the host too.
- Relay: melchior:6464 (Tailscale 100.96.183.93 / LAN 192.168.1.154).
