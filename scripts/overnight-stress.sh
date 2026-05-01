#!/bin/bash
# overnight-stress.sh
#
# Runs the full demo stress suite with leak detection + render verification
# + baseline regression check. Designed to be triggered via launchd at 0100
# local. Writes a timestamped log + summary to /tmp/occt-overnight/.
#
# Requires: macOS user is logged in with GUI session active. The macOS
# SwiftUI app needs a window-server context for SwiftUI .onAppear to fire,
# which drives the test runner. caffeinate -d keeps the display from
# sleeping during the run.

set -u

REPO="/Users/elb/Projects/OCCTSwiftViewport"
OUT_DIR="/tmp/occt-overnight"
TS=$(date "+%Y%m%d-%H%M%S")
LOG="$OUT_DIR/run-$TS.log"
SUMMARY="$OUT_DIR/summary-$TS.txt"

mkdir -p "$OUT_DIR"
cd "$REPO" || { echo "Repo not found at $REPO" >> "$LOG"; exit 1; }

{
  echo "═══════════════════════════════════════════════════════════════"
  echo "  Overnight stress run — $(date)"
  echo "═══════════════════════════════════════════════════════════════"
  echo "Working directory: $(pwd)"
  echo "Git HEAD: $(git rev-parse --short HEAD)"
  echo
} > "$LOG"

# Rebuild to pick up any in-flight changes since the last run.
echo "── building ──" >> "$LOG"
swift build >> "$LOG" 2>&1
build_exit=$?
if [ $build_exit -ne 0 ]; then
  echo "BUILD FAILED (exit $build_exit) — aborting" >> "$LOG"
  cp "$LOG" "$SUMMARY"
  exit 2
fi

# Run with all stress flags engaged. caffeinate -d prevents display sleep.
# 3 iterations exercises the leak detector; --render verifies Metal can
# rasterize each demo; --baseline-check fails any 2x regression.
echo "── running stress test (3 iterations, render, baseline check) ──" >> "$LOG"
caffeinate -d .build/debug/OCCTSwiftMetalDemo \
  --test-all-demos \
  --iterations 3 \
  --render \
  --baseline-check Tests/baselines/demo-timings.json \
  >> "$LOG" 2>&1
demo_exit=$?

# Summary: extract the final RESULTS block + any failures + RSS trace.
{
  echo "═══════════════════════════════════════════════════════════════"
  echo "  Overnight stress run — $(date)"
  echo "═══════════════════════════════════════════════════════════════"
  echo "Demo exit code: $demo_exit"
  echo "Build commit:   $(git rev-parse --short HEAD)"
  echo
  echo "── RESULTS block ──"
  awk '/^═+$/{p=!p; if(p)next} p' "$LOG" | tail -40 2>/dev/null || tail -50 "$LOG"
  echo
  echo "── Failed demos ──"
  grep -E "^❌" "$LOG" || echo "(none)"
  echo
  echo "── Render failures ──"
  grep "RENDER-FAIL" "$LOG" || echo "(none)"
  echo
  echo "── Regressions ──"
  grep "REGRESSION" "$LOG" || echo "(none)"
  echo
  echo "── RSS trace ──"
  grep -E "^  (initial|after iter|Net RSS)" "$LOG" || echo "(none)"
  echo
  echo "Full log: $LOG"
} > "$SUMMARY"

exit $demo_exit
