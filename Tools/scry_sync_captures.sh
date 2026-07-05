#!/usr/bin/env bash
#
# One command to turn on-device Scry captures into test-corpus entries — no
# manual file transfer. The GrimoraScry harness writes each labeled scan into its
# iCloud Drive container, so the captures sync to this Mac on their own; this
# script materializes them, imports them into the corpus, refreshes the test
# catalog if new cards appeared, and prints the new cards so an agent can read
# them off. Intended to be run by an agent when you ask it to "generate tests
# from the new scans".
#
# Usage:
#   Tools/scry_sync_captures.sh                 # import from the iCloud Captures folder
#   Tools/scry_sync_captures.sh --tests         # …and run the Scry corpus + scene tests
#   Tools/scry_sync_captures.sh --dry-run       # preview only, write nothing
#   Tools/scry_sync_captures.sh /path/to/Captures   # import from a specific folder
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CAPTURES="$HOME/Library/Mobile Documents/iCloud~com~samwagner~GrimoraScry/Documents/Captures"

CAPTURES_DIR=""
RUN_TESTS=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --tests) RUN_TESTS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
    *) CAPTURES_DIR="$arg" ;;
  esac
done
CAPTURES_DIR="${CAPTURES_DIR:-$DEFAULT_CAPTURES}"

if [ ! -d "$CAPTURES_DIR" ]; then
  echo "Captures folder not found:" >&2
  echo "  $CAPTURES_DIR" >&2
  echo >&2
  echo "Is Grimora Scry signed into the same iCloud account as this Mac, and has" >&2
  echo "it captured at least one card? (The folder appears once the first capture" >&2
  echo "syncs.) You can also pass an explicit folder as the first argument." >&2
  exit 1
fi

echo "==> Materializing iCloud files"
echo "    $CAPTURES_DIR"
# Ask iCloud to download any not-yet-local files, then wait for the ".icloud"
# placeholder stubs to clear (bounded, so a stalled sync can't hang the run).
if command -v brctl >/dev/null 2>&1; then
  brctl download "$CAPTURES_DIR" >/dev/null 2>&1 || true
fi
for _ in $(seq 1 60); do
  remaining="$(find "$CAPTURES_DIR" -maxdepth 1 -name '*.icloud' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$remaining" -eq 0 ] && break
  echo "    waiting on $remaining iCloud file(s) to download…"
  sleep 2
done

SUMMARY_JSON="${TMPDIR:-/tmp}/scry-last-import.json"
IMPORT_ARGS=(--summary-json "$SUMMARY_JSON")
[ "$DRY_RUN" -eq 1 ] && IMPORT_ARGS+=(--dry-run)

echo "==> Importing captures into the corpus"
# The importer maps verdicts → expectations, appends the manifests, moves
# processed captures to <Captures>/imported/ (that move syncs back and clears the
# phone's list), and prints the new cards. It exits non-zero when the catalog is
# missing new cards — handled below — so don't let -e abort here.
set +e
python3 "$REPO_ROOT/Tools/scry_import_captures.py" "$CAPTURES_DIR" "${IMPORT_ARGS[@]}"
set -e

if [ "$DRY_RUN" -eq 1 ]; then
  echo "==> Dry run — no catalog rebuild, no tests."
  exit 0
fi

echo "==> Checking test-catalog coverage"
if ! python3 "$REPO_ROOT/Tools/scry_build_corpus_catalog.py" --check >/dev/null 2>&1; then
  echo "    new cards missing from the catalog — fetching printings from Scryfall"
  echo "    (rate-limited; this can take a few minutes)…"
  python3 "$REPO_ROOT/Tools/scry_build_corpus_catalog.py"
else
  echo "    catalog already covers every entry."
fi

if [ "$RUN_TESTS" -eq 1 ]; then
  echo "==> Running Scry corpus + scene tests"
  SCRY_REPORT_DIR="${SCRY_REPORT_DIR:-${TMPDIR:-/tmp}/scry-report}"
  mkdir -p "$SCRY_REPORT_DIR"
  ( cd "$REPO_ROOT" && SCRY_REPORT_DIR="$SCRY_REPORT_DIR" \
      swift test --package-path GrimoraKit --filter 'ScryCorpusTests|ScrySceneTests' )
  echo "    full reports in $SCRY_REPORT_DIR"
fi

echo
echo "Done. New cards are listed above; machine-readable summary at:"
echo "  $SUMMARY_JSON"
