#!/bin/bash
# Divergence-hunt campaign runner (run on the HOST, not in the container).
# Repeats fresh-container 8-instance lockstep runs and tallies outcomes, to turn
# "1-of-3 diverged" into a real rate — and, with a loss-injection ROM, to make the
# stall/render schedule adversarial and RAISE the reproduction probability.
#
# Usage:
#   ./campaign8.sh [N_RUNS] [ROM]
#     N_RUNS  number of runs (default 10)
#     ROM     ROM file in /mnt/micron/jsuppe/netpak to stage as mk64_test.z64
#             (default: leave whatever is already staged)
# Typical campaign:
#   1. Build test ROM (all lockstep test flags 1, NET_LOCKSTEP_LOSS 0)
#      -> cp to netpak/mk64_test_clean.z64
#   2. Build again with NET_LOCKSTEP_LOSS 1
#      -> cp to netpak/mk64_test_loss.z64
#   3. ./campaign8.sh 10 mk64_test_clean.z64   # base rate
#   4. ./campaign8.sh 10 mk64_test_loss.z64    # adversarial rate (expect higher)
# Results: netpak/campaign_results.txt (one line per run + summary).
set -u
N=${1:-10}
ROM=${2:-}
DIR=/mnt/micron/jsuppe/netpak
OUT=$DIR/campaign_results.txt
if [ -n "$ROM" ]; then cp "$DIR/$ROM" "$DIR/mk64_test.z64" || exit 1; fi
echo "=== campaign $(date '+%F %T') N=$N ROM=${ROM:-<staged>} ===" >> "$OUT"

IDENT=0; DIV=0; FLAKE=0
for run in $(seq 1 "$N"); do
  docker rm -f npharness >/dev/null 2>&1
  docker run -d --rm --name npharness --network host \
    --device /dev/dri/renderD128 --device /dev/dri/card1 \
    -v /home/melchior/dev/ares:/src -v "$DIR":/work \
    ares-builder:latest sleep 10800 >/dev/null 2>&1
  sleep 2
  RES=$(docker exec -e DWELL=140 npharness bash /work/harness8.sh 2>&1 | grep -E "IDENTICAL|DIVERGES|fewer than|NO COMMON" | head -1)
  case "$RES" in
    *IDENTICAL*) IDENT=$((IDENT+1)); TAG=IDENTICAL ;;
    *DIVERGES*)  DIV=$((DIV+1));     TAG="DIVERGED: $RES"
                 # preserve the divergent run's logs for analysis
                 mkdir -p "$DIR/div_run_$run"; cp "$DIR"/np64out/*.log "$DIR/div_run_$run/" 2>/dev/null ;;
    *)           FLAKE=$((FLAKE+1)); TAG=LAUNCH-FLAKE ;;
  esac
  echo "run $run: $TAG" | tee -a "$OUT"
done
docker rm -f npharness >/dev/null 2>&1
echo "SUMMARY: identical=$IDENT diverged=$DIV flakes=$FLAKE (of $N)" | tee -a "$OUT"
