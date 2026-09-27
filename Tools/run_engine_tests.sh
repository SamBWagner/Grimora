#!/bin/zsh
set -euo pipefail

# Runs the Grimora data-engine test suites.
#
#   Tools/run_engine_tests.sh            # offline, deterministic (golden pipeline + engine glue) — CI-safe
#   Tools/run_engine_tests.sh --live     # the above PLUS the lightweight live "real pull" checks
#   Tools/run_engine_tests.sh --full     # the above PLUS the full real catalog build (downloads ~hundreds of MB)
#   Tools/run_engine_tests.sh --update-golden   # regenerate the checked-in golden snapshot
#   Tools/run_engine_tests.sh --semantic-publication   # opt-in A→B→C publication evidence
#
# The deterministic tests need no network and form the CI gate. The live tests hit Scryfall +
# MTGJSON and are otherwise skipped. Semantic publication evidence requires both
# GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR and GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR; without them
# this command exits successfully without running the private-data harness. Set the optional
# GRIMORA_SEMANTIC_PUBLICATION_BASE_BUILD_SECONDS to include the measured full-build wall time.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/GrimoraKit"

FILTER=(
  --filter CatalogGoldenPipelineTests
  --filter EngineBuildIntegrationTests
  --filter CatalogManifestCompatibilityTests
  --filter CatalogStorageTests
  --filter CatalogContentDigestTests
  --filter CatalogChainTests
  --filter SemanticCatalogStorageTests
  --filter OracleTagsSemanticEnrichmentTests
  --filter CatalogDeltaRoundTripTests
  --filter SemanticPublicationEvidenceTests
  --filter catalogRoutesServeManifestRedirectsAndHealth
)
MODE="offline"

for arg in "$@"; do
  case "$arg" in
    --live) MODE="live" ;;
    --full) MODE="full" ;;
    --update-golden) MODE="update" ;;
    --semantic-publication) MODE="semantic-publication" ;;
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
  semantic-publication)
    if [[ -z "${GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR:-}" \
      && -z "${GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR:-}" ]]; then
      echo "Semantic publication evidence skipped: opt-in environment is not set."
      exit 0
    fi
    if [[ -z "${GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR:-}" \
      || -z "${GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR:-}" ]]; then
      echo "semantic publication requires both GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR and GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR" >&2
      exit 2
    fi
    GRIMORA_SEMANTIC_PUBLICATION_ENABLED=1 swift test --package-path "$PACKAGE_DIR" \
      --filter SemanticPublicationEvidenceTests.semanticPublicationEvidenceFromRealBaseBuild
    ;;
esac
