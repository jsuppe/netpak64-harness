
## Build hygiene (2026-07-05, learned the hard way)
- `grep -E "error"` MISSES `make: *** Error 1` (capital E). Always `grep -iE "error"`
  or better: verify the ROM md5 CHANGED after a build that should change it.
- `cp` after `make` on separate lines stages a STALE ROM when make fails.
  Always `make ... && cp ...`.
- Flag sed + make in one block: confirm the make actually rebuilt (`Nothing to be
  done` = stale flags in the ROM). Product-flag ROM in the harness = attract demo,
  zero pokes — looks exactly like a boot break.
- Racing-overlay .c files (collision.c, render_courses.c, race_logic.c...) must NOT
  gain new .bss/data — link fails with "defined in discarded section" or worse,
  silently corrupts layout. Put diag globals in net_race.c (netbss) and extern them.
- Container images lack xdpyinfo/ffmpeg/import/xwd. HAVE: scrot, xdotool. X liveness
  check = `[ -S /tmp/.X11-unix/X$DN ]`.

## State-inspection probe (v41+)
- gdbrace.sh: 2-instance race with ares GDB stubs (alice :9124, bob :9125).
- camprobe.py: continue/interrupt sampling of both stubs; checks A sim-camera
  identity across consoles, B joiner local-cam tracks OWN kart, C kart0
  position agreement (delay-window bounded). gNetProbeAnchors (netbss, filled
  at net_lockstep_reset) exposes the static camera state addresses.
- Stub facts: connect HALTS emulation; raw 0x03 = interrupt; addresses must
  match the STAGED test ROM's map (rebuild shifts gPlayers/camera1).
- Known gaps: 1-lap test races end fast (sample early); check A reads a
  constant 54.8deg — comparison anchor suspect, refine before trusting it.
