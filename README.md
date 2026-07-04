# netpak64-harness

Headless test harness for NetPak64 online mk64: launches 2/4/8 paired ares
instances against a local np64-relay, auto-navigates into an online lockstep
race, tiles the windows for combined screenshots, and decodes the ROM's
debug-poke channel (NP64_TRACE_IO) to compare per-frame input/sim hashes
across instances.

- harness2/4/8.sh — N-instance paired race runners (tiling + event shots)
- campaign8.sh    — repeated fresh-container runs; tallies identical/diverged
- decode_*.py     — poke-stream decoders (sim hash, per-kart, inputs, seed...)
- det_run.sh      — offline two-instance determinism probe
- ares_netpak.patch — NetPak64 device patch for a stock ares checkout

Companion repos: mk64-netpak64 (game), ares-netpak64 (emulator+device),
np64-relay (relay server). ROMs are never stored here.
