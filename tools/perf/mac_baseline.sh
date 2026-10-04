#!/bin/zsh
# Mac performance baseline (3.0.9 roadmap Track 1). Builds an UNSIGNED Debug copy of the Mac app,
# launches it with `--perfSeed=N` (synthetic on-disk scratch store, fixed debug key: no Keychain,
# no CloudKit, no notifications, never the real store; see PerfSeed.swift), triggers app
# records the PerfSignpost intervals with xctrace (subsystem com.lokesh.mirror, category perf) and prints them.
# The app opens a window for PERF_SECONDS (default 25). Usage: tools/perf/mac_baseline.sh [N=2000]
set -euo pipefail
N=${1:-2000}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DD=${PERF_DERIVED_DATA:-/private/tmp/mirror-perf-derived}
OUT=${PERF_OUT:-/private/tmp/mirror-perf-$N}
mkdir -p "$OUT"
xcodebuild build -project "$ROOT/mirror.xcodeproj" -scheme mirror -destination 'platform=macOS' \
  -configuration Debug -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; exit 1; }
APP=$(ls -d "$DD"/Build/Products/Debug/*.app | head -1)
BIN="$APP/Contents/MacOS/$(defaults read "$APP/Contents/Info" CFBundleExecutable)"
TRACE="$OUT/run.trace"; rm -rf "$TRACE"
# Signposts only reach a trace while a tracing tool is attached (not the unified log).
xcrun xctrace record --instrument os_signpost --time-limit ${PERF_SECONDS:-25}s --output "$TRACE" --launch -- "$BIN" "--perfSeed=$N" > "$OUT/xctrace.log" 2>&1 || true  # exits non-zero when the time limit ends it
xcrun xctrace export --input "$TRACE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' > "$OUT/signposts.xml"
python3 "$ROOT/tools/perf/signposts.py" "$OUT/signposts.xml"
echo "raw: $OUT (run twice: the first run seeds the store)"
