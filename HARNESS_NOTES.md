
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

## Input-tape REPLAY harness (2026-07-08)
- Tape v2 ('NTP2', hdr 0x30 @0x80440000, data +0x30, sim-hash lane @0x80520000
  one u32/16df): records course/cc/delay/chars so a race can be REPLAYED.
- tapeload.py <gdbport> <in.tape>: pushes a tape into a running ares and ARMS
  it ('NTPR'). Then host a room ALONE and START: the ROM forces the recorded
  course/class/roster/delay and drives all karts from the tape, checking each
  16th frame's sim hash against the recorded lane. Log verdict:
  REPLAY-START ... REPLAY-END df=N checked=K bad=0 OK  (grep ares log).
- replaytest.sh (container): record alice+bob -> dump -> solo replay -> PASS/FAIL.
- .m64 files remain viewing artifacts (Mupen scrubbing); the .tape is the
  replay format — .m64 can't sync (menu path isn't frame-reproducible).

## THE CANONICAL ARES BUILD (2026-07-08, learned over 3 hours of ghosts)
- LIVES AT /home/melchior/dev/ares (root-only; containers mount it as /src).
  /mnt/micron/jsuppe/netpak/ares is a STALE Jul-2 copy: its DeviceCore lacks
  the ROOM/NAME regs (0x64/0x6C read 0xFFFF -> havePreset latches TRUE with a
  garbage code, isAlice/doRename latch false -> autopilot NEVER presses START,
  every race silently never begins). If a container harness acts haunted,
  check the /src mount FIRST: `ls -la /src/build/desktop-ui/ares` (should be
  fresh, root-owned ~550MB; the stale one is jsuppe-owned, dated Jul 2).
- NP64_TRACE_IO has a 4000-LINE BUDGET (netpak.cpp _traceBudget): traces that
  just STOP mid-run are the budget running dry, not the ROM dying. It also
  slows ares hard; keep it off unless needed and treat its end as truncation.
- NVIDIA driver outage 07-08 17:19 -> 07-09 morning: the reboot switched to
  kernel 6.17.0-35 which had NO nvidia module (linux-modules-nvidia-570 meta
  lagged at -22). FIXED by installing the module package (now 580.159.03).
  Symptom key: nvidia-smi fails + renderD128 gone -> ares software-renders at
  ~1/3 speed and every 60fps-tuned dwell starves. If it recurs after a kernel
  update: sudo apt install linux-modules-nvidia-<ver>-generic-hwe-24.04.
- osSyncPrintf DOES reach instance logs (isPrintfInit runs at boot; the ares
  fork mirrors ISViewer to stdout with ARES_ISV=1). Grep for lowercase
  'netpak:'; device-side lines are '[NetPak64]' (capital P).

## ROM-LAYOUT-SENSITIVE SIM (2026-07-09, solved after 3 red herrings)
- MK64 sim trajectories are LAYOUT-SENSITIVE: rebuilding with ANY code-size
  change in .main (even in provably render-only functions) produces a slightly
  different sim trajectory. Suspect an out-of-bounds/aliased table read in sim
  whose neighboring bytes shift with layout. NOT yet root-caused.
- Consequences: (1) input tapes + their hash lanes are BUILD-SPECIFIC — a tape
  only verifies the exact ROM that recorded it; re-record after every build
  whose function sizes changed. (2) cross-build replay FAIL is NOT evidence a
  change broke determinism — always judge by within-build record+replay.
  (3) online lockstep is unaffected (peers must run identical ROMs; VERSION-gated).
- Evidence: 4 edits in code_80057C60.c. The ONLY one whose cross-build replay
  PASSED kept the function at exactly the same instruction count (203) = no
  layout shift. All size-changing edits (incl. pure perf brackets and a
  bit-exact trig rewrite) failed cross-build replay with the identical canary
  signature, and each passed within-build record+replay 100%.
- Canary fact: on the autodrive workload, ANY layout shift first shows at hash
  check 21 (df~336) kart 4 — same signature for unrelated builds. Do not read
  "same check index" as "same bug".
- Verdict header decode (0x80440024/28/2C): rsvd[1]=(firstBadIdx<<16)|checked,
  rsvd[2]=(kartMask<<16)|bad. checked=0x150247 means firstBad=0x15, checked=0x247.
- Camera-dependent gating of particle updates (unk_002 SIDE_OF_KART) was
  killed on FALSE evidence (the layout effect); it may actually be safe, but
  re-attempt only with the layout question settled: within-build replay PASS +
  harness8 PASS (8 instances = 8 different cameras) is the required gate.
