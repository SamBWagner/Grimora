#!/bin/bash
#
# test-fast.sh — fast inner-loop UI test runner.
#
# The full release matrix runs the UI suite on macOS + iPhone + iPad + visionOS,
# serially, with a clean build each time — that's the ~40 min cycle. For the
# inner dev loop you almost never need all of that. This script:
#
#   * runs ONE platform (iPhone simulator by default),
#   * reuses a persistent DerivedData dir + a pre-booted simulator,
#   * builds once (build-for-testing) then runs (test-without-building) so
#     unchanged code isn't recompiled,
#   * runs test classes in parallel across simulator clones,
#   * lets you target a single class/method with -o.
#
# Shared app logic is covered by the fast `swift test` package tests in
# GrimoraKit; keep the full 4-platform UI matrix for pre-merge / CI.
#
# Examples:
#   Tools/test-fast.sh                                  # all iPhone UI tests, parallel
#   Tools/test-fast.sh -o GrimoraiOSUITests/SearchRefineWorkflowUITests
#   Tools/test-fast.sh -p ipad -w 6
#   Tools/test-fast.sh -p vision
#   Tools/test-fast.sh -p mac                           # serial (macOS UI tests don't parallelize cleanly)
#   Tools/test-fast.sh -c                               # force a clean rebuild
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLATFORM="ios"
WORKERS=4
CLEAN=0
ONLY_ARGS=()

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
  cat <<'EOF'
Options:
  -p, --platform   ios | ipad | vision | mac   (default: ios)
  -w, --workers N  parallel simulator workers   (default: 4; ignored on mac)
  -o, --only ID    -only-testing identifier (repeatable), e.g.
                   GrimoraiOSUITests/SearchRefineWorkflowUITests[/testFoo]
  -c, --clean      wipe this platform's DerivedData before building
  -h, --help       show this help

Tip: pipe through `xcbeautify` if installed for tidier output.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--platform) PLATFORM="${2:?}"; shift 2 ;;
    -w|--workers)  WORKERS="${2:?}"; shift 2 ;;
    -o|--only)     ONLY_ARGS+=("-only-testing:${2:?}"); shift 2 ;;
    -c|--clean)    CLEAN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Map platform -> scheme + simulator device-name prefix.
SIM_PREFIX=""
case "$PLATFORM" in
  ios)    SCHEME="GrimoraiOS";      SIM_PREFIX="iPhone";       SIM_PLATFORM="iOS Simulator" ;;
  ipad)   SCHEME="GrimoraiOS";      SIM_PREFIX="iPad";         SIM_PLATFORM="iOS Simulator" ;;
  vision) SCHEME="GrimoraVisionOS"; SIM_PREFIX="Apple Vision"; SIM_PLATFORM="visionOS Simulator" ;;
  mac)    SCHEME="GrimoraMac" ;;
  *) echo "Unknown platform '$PLATFORM' (want: ios | ipad | vision | mac)" >&2; exit 2 ;;
esac

# Resolve the destination. macOS needs no simulator; everything else picks the
# newest available device matching the name prefix and boots it for reuse.
if [[ "$PLATFORM" == "mac" ]]; then
  DESTINATION="platform=macOS"
else
  UDID="$(
    xcrun simctl list devices available -j | SIM_PREFIX="$SIM_PREFIX" python3 -c '
import json, os, sys
prefix = os.environ["SIM_PREFIX"]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith(prefix):
            print(device["udid"]); sys.exit(0)
sys.exit("No available simulator matching %r — create one in Xcode > Settings > Components." % prefix)
'
  )"
  DESTINATION="platform=${SIM_PLATFORM},id=${UDID}"
  echo "==> Booting simulator ${UDID} (reused if already running)"
  xcrun simctl boot "$UDID" 2>/dev/null || true
fi

DERIVED="$ROOT/.build/test-fast/$SCHEME"
[[ "$CLEAN" -eq 1 ]] && { echo "==> Clean: removing $DERIVED"; rm -rf "$DERIVED"; }

COMMON=(
  -project Grimora.xcodeproj
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED"
  CODE_SIGNING_ALLOWED=NO
)

PARALLEL=()
if [[ "$PLATFORM" != "mac" && "$WORKERS" -gt 1 ]]; then
  PARALLEL=(-parallel-testing-enabled YES -parallel-testing-worker-count "$WORKERS")
fi

echo "==> [$PLATFORM] scheme=$SCHEME workers=$([[ ${#PARALLEL[@]} -gt 0 ]] && echo "$WORKERS" || echo "1 (serial)")"
echo "==> destination: $DESTINATION"
[[ ${#ONLY_ARGS[@]} -gt 0 ]] && echo "==> only: ${ONLY_ARGS[*]#-only-testing:}"

START=$SECONDS

echo "==> build-for-testing (incremental; reuses $DERIVED)"
xcodebuild build-for-testing "${COMMON[@]}"

echo "==> test-without-building"
# ${arr[@]+"${arr[@]}"} guards empty-array expansion under `set -u` on bash 3.2 (macOS /bin/bash).
xcodebuild test-without-building "${COMMON[@]}" ${PARALLEL[@]+"${PARALLEL[@]}"} ${ONLY_ARGS[@]+"${ONLY_ARGS[@]}"}

echo "==> done in $((SECONDS - START))s"
