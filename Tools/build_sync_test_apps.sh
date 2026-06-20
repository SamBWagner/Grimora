#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/Grimora.xcodeproj"
DERIVED_ROOT="${GRIMORA_SYNC_TEST_DERIVED_DATA:-/private/tmp/grimora-sync-test}"
TEAM_ID="${DEVELOPMENT_TEAM:-BJPQVZR5PZ}"
BUNDLE_ID="${GRIMORA_SYNC_TEST_BUNDLE_ID:-com.samwagner.Grimora.SyncTest}"
PLATFORM="${1:-all}"

build_scheme() {
  local scheme="$1"
  local destination="$2"
  local derived_data="$3"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$scheme" \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    INFOPLIST_KEY_CFBundleDisplayName="Grimora Sync Test" \
    build
}

cd "$ROOT_DIR"
xcodegen generate

case "$PLATFORM" in
  macos)
    build_scheme GrimoraMac "platform=macOS" "$DERIVED_ROOT/macos"
    ;;
  ios|ipados)
    build_scheme GrimoraiOS "generic/platform=iOS" "$DERIVED_ROOT/ios"
    ;;
  visionos)
    build_scheme GrimoraVisionOS "generic/platform=visionOS" "$DERIVED_ROOT/visionos"
    ;;
  all)
    build_scheme GrimoraMac "platform=macOS" "$DERIVED_ROOT/macos"
    build_scheme GrimoraiOS "generic/platform=iOS" "$DERIVED_ROOT/ios"
    build_scheme GrimoraVisionOS "generic/platform=visionOS" "$DERIVED_ROOT/visionos"
    ;;
  *)
    echo "Usage: Tools/build_sync_test_apps.sh [macos|ios|ipados|visionos|all]" >&2
    exit 1
    ;;
esac
