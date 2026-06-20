#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/GrimoraKit"
INSTALL_DIR="$HOME/Library/Application Support/GrimoraDataEngine/bin"
LOG_DIR="$HOME/Library/Logs/GrimoraDataEngine"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LABEL="com.samwagner.GrimoraDataEngine"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
ARTIFACTS_BUCKET="${TIGRIS_ARTIFACTS_BUCKET:-grimora-catalog-artifacts-bjpqvzr5pz}"
METADATA_BUCKET="${TIGRIS_METADATA_BUCKET:-grimora-catalog-metadata-bjpqvzr5pz}"
CATALOG_PUBLIC_BASE_URL="${GRIMORA_CATALOG_PUBLIC_BASE_URL:-https://grimora-data-api.fly.dev/v1/catalog}"

swift build --package-path "$PACKAGE_DIR" -c release --product grimora-data-engine
BIN_PATH="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)/grimora-data-engine"

mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
cp "$BIN_PATH" "$INSTALL_DIR/grimora-data-engine"
chmod 755 "$INSTALL_DIR/grimora-data-engine"

sed "s|__ENGINE_PATH__|$INSTALL_DIR/grimora-data-engine|g" \
  "$PACKAGE_DIR/Resources/$LABEL.plist" \
  | sed "s|__LOG_DIR__|$LOG_DIR|g" \
  | sed "s|__ARTIFACTS_BUCKET__|$ARTIFACTS_BUCKET|g" \
  | sed "s|__METADATA_BUCKET__|$METADATA_BUCKET|g" \
  | sed "s|__CATALOG_PUBLIC_BASE_URL__|$CATALOG_PUBLIC_BASE_URL|g" > "$PLIST_PATH"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed and started $LABEL"
