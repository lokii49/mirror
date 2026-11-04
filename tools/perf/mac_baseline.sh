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
# PERF_OPTIMIZED=1: Debug configuration (keeps --perfSeed) compiled with -O, closer to what users run.
# Use its own PERF_DERIVED_DATA so the two builds don't keep invalidating each other.
OPT_FLAGS=""
[[ "${PERF_OPTIMIZED:-0}" == 1 ]] && OPT_FLAGS="SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s"
xcodebuild build -project "$ROOT/mirror.xcodeproj" -scheme mirror -destination 'platform=macOS' \
  -configuration Debug -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO ${=OPT_FLAGS} > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; exit 1; }
APP=$(ls -d "$DD"/Build/Products/Debug/*.app | head -1)
BIN="$APP/Contents/MacOS/$(defaults read "$APP/Contents/Info" CFBundleExecutable)"
# Record every process and start this build's binary directly. `xctrace record --launch` resolved
# the bundle through Launch Services and started the INSTALLED release app in /Applications instead
# (seen 2026-11-04, also with a changed bundle id): Release ignores --perfSeed, so that opened the
# owner's real journal.
TRACE="$OUT/run.trace"; rm -rf "$TRACE"
# Signposts only reach a trace while a tracing tool is attached (not the unified log).
xcrun xctrace record --instrument os_signpost --all-processes --time-limit ${PERF_SECONDS:-25}s --output "$TRACE" > "$OUT/xctrace.log" 2>&1 &
XCTRACE=$!
sleep 3
"$BIN" "--perfSeed=$N" > "$OUT/app.log" 2>&1 &
APPPID=$!
sleep 3
# Stop at once if anything other than this build's binary is running with the seed argument.
if pgrep -fl -- "--perfSeed=$N" | grep -v "$DD" | grep -q MirrorNotes; then
  pgrep -fl -- "--perfSeed=$N"; echo "ABORT: a MirrorNotes outside $DD was launched; killing it" >&2
  pkill -9 -f -- "--perfSeed=$N"; kill $XCTRACE 2>/dev/null; exit 2
fi
wait $XCTRACE || true  # exits non-zero when the time limit ends it
kill $APPPID 2>/dev/null || true
# Leave no extra copy registered with Launch Services (stale copies grey out the notification icon).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
xcrun xctrace export --input "$TRACE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' > "$OUT/signposts.xml"
python3 "$ROOT/tools/perf/signposts.py" "$OUT/signposts.xml"
grep -q perfSeed "$OUT/signposts.xml" || echo "WARNING: no perfSeed signpost: the seeded Debug build may not be what ran" >&2
echo "raw: $OUT (run twice: the first run seeds the store)"
