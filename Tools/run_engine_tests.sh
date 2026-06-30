#!/bin/zsh
set -euo pipefail

# Runs the Grimora data-engine test suites.
#
#   Tools/run_engine_tests.sh            # offline, deterministic (golden pipeline + engine glue) — CI-safe
#   Tools/run_engine_tests.sh --live     # the above PLUS the lightweight live "real pull" checks
#   Tools/run_engine_tests.sh --full     # the above PLUS the full real catalog build (downloads ~hundreds of MB)
#   Tools/run_engine_tests.sh --update-golden   # regenerate the checked-in golden snapshot
#
# The deterministic tests need no network and form the CI gate. The live tests hit Scryfall +
# MTGJSON and are otherwise skipped.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/GrimoraKit"

FILTER=(--filter CatalogGoldenPipelineTests --filter EngineBuildIntegrationTests)
MODE="offline"

for arg in "$@"; do
  case "$arg" in
    --live) MODE="live" ;;
    --full) MODE="full" ;;
    --update-golden) MODE="update" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  offline)
    swift test --package-path "$PACKAGE_DIR" "${FILTER[@]}"
    ;;
  update)
    GRIMORA_UPDATE_GOLDEN=1 swift test --package-path "$PACKAGE_DIR" --filter CatalogGoldenPipelineTests
    echo "Regenerated golden snapshot."
    ;;
  live)
    GRIMORA_LIVE_TESTS=1 swift test --package-path "$PACKAGE_DIR" \
      "${FILTER[@]}" --filter LiveDataSourceTests
    ;;
  full)
    GRIMORA_LIVE_TESTS=1 GRIMORA_LIVE_FULL_BUILD=1 swift test --package-path "$PACKAGE_DIR" \
      "${FILTER[@]}" --filter LiveDataSourceTests
    ;;
esac
