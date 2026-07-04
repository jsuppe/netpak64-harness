# Human lockstep build — on-device test kit (balthazar)

## What this is
First build where HUMANS play the lockstep online engine (one shared
deterministic simulation; all prior testing was robot-driven).
ROM: `mk64_netpak_human.z64` (md5 b542d616) — lockstep ON, all test
automation OFF, real host/join flow.

## One-time: update ares on balthazar
The ROM needs the CURRENT NetPak64 device (room-code register + fixes).
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
