#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/grimora-sync-sim-tests"
DERIVED_DATA="$TMP_ROOT/DerivedData"
RELAY_PORT="${GRIMORA_SYNC_RELAY_PORT:-18765}"
RELAY_URL="http://127.0.0.1:$RELAY_PORT/"
BUNDLE_ID="com.samwagner.Grimora"

mkdir -p "$TMP_ROOT"

cleanup() {
  if [[ -n "${RELAY_PID:-}" ]]; then
    kill "$RELAY_PID" 2>/dev/null || true
    wait "$RELAY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

rm -f "$TMP_ROOT/relay.log"
python3 "$ROOT/Tools/grimora_sync_relay.py" \
  --port "$RELAY_PORT" >"$TMP_ROOT/relay.log" 2>&1 &
RELAY_PID=$!

for _ in $(seq 1 40); do
  if ! kill -0 "$RELAY_PID" 2>/dev/null; then
    cat "$TMP_ROOT/relay.log" >&2
    exit 1
  fi
  if curl -fsS "$RELAY_URL/state" >/dev/null; then
    break
  fi
  sleep 0.1
done
curl -fsS "$RELAY_URL/state" >/dev/null
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${RELAY_URL}reset" >/dev/null

DEVICES="$(
  xcrun simctl list devices available -j | python3 -c '
import json
import sys

data = json.load(sys.stdin)["devices"]
iphone = None
ipad = None
for runtime in sorted(data, reverse=True):
    for device in data[runtime]:
        if not device.get("isAvailable"):
            continue
        name = device["name"]
        if iphone is None and name.startswith("iPhone"):
            iphone = device["udid"]
        if ipad is None and name.startswith("iPad"):
            ipad = device["udid"]
    if iphone and ipad:
        break
if not iphone or not ipad:
    raise SystemExit("An available iPhone and iPad simulator are required.")
print(iphone)
print(ipad)
'
)"
IPHONE_UDID="$(printf '%s\n' "$DEVICES" | sed -n '1p')"
IPAD_UDID="$(printf '%s\n' "$DEVICES" | sed -n '2p')"

xcodebuild \
  -project "$ROOT/Grimora.xcodeproj" \
  -scheme GrimoraiOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'Grimora.app' -print -quit)"
test -n "$APP_PATH"

container_path() {
  local udid="$1"
  xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data
}

database_path() {
  local udid="$1"
  printf '%s\n' "$(container_path "$udid")/Library/Application Support/Grimora/Database-v2/User.sqlite"
}

for udid in "$IPHONE_UDID" "$IPAD_UDID"; do
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  if xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data >/dev/null 2>&1; then
    xcrun simctl uninstall "$udid" "$BUNDLE_ID"
  fi
  if xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data >/dev/null 2>&1; then
    printf 'FAIL: simulator app data was not removed for %s\n' "$udid" >&2
    exit 1
  fi
  xcrun simctl install "$udid" "$APP_PATH"
  mkdir -p "$(dirname "$(database_path "$udid")")"
done

list_exists() {
  local udid="$1"
  local name="$2"
  local database
  database="$(database_path "$udid")"
  [[ -f "$database" ]] || return 1
  [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM card_lists WHERE name = '$name';")" == "1" ]]
}

list_missing() {
  ! list_exists "$1" "$2"
}

list_id() {
  local udid="$1"
  local name="$2"
  sqlite3 "$(database_path "$udid")" \
    "SELECT id FROM card_lists WHERE name = '$name' LIMIT 1;"
}

relay_list_exists() {
  local name="$1"
  curl -fsS "$RELAY_URL/state" | python3 -c '
import json
import sys

name = sys.argv[1]
snapshots = json.load(sys.stdin)["state"]["snapshots"]
lists = snapshots[0]["listSnapshot"]["lists"] if snapshots else []
raise SystemExit(0 if any(value["name"] == name for value in lists) else 1)
' "$name"
}

relay_tombstone_exists() {
  local record_id="$1"
  curl -fsS "$RELAY_URL/state" | python3 -c '
import json
import sys

record_id = sys.argv[1]
snapshots = json.load(sys.stdin)["state"]["snapshots"]
tombstones = snapshots[0]["deletedEntities"] if snapshots else []
raise SystemExit(
    0
    if any(
        value["entityType"] == "cardList" and value["recordID"] == record_id
        for value in tombstones
    )
    else 1
)
' "$record_id"
}

wait_for() {
  local description="$1"
  shift
  for _ in $(seq 1 160); do
    if "$@"; then
      printf 'PASS: %s\n' "$description"
      return 0
    fi
    sleep 0.25
  done
  printf 'FAIL: %s\n' "$description" >&2
  return 1
}

launch_app() {
  local udid="$1"
  shift
  env \
    SIMCTL_CHILD_GRIMORA_TEST_ENABLE_CLOUD_SYNC=1 \
    SIMCTL_CHILD_GRIMORA_TEST_CLOUD_SYNC_RELAY_URL="$RELAY_URL" \
    SIMCTL_CHILD_GRIMORA_TEST_DATABASE_PATH="$(database_path "$udid")" \
    SIMCTL_CHILD_GRIMORA_DISABLE_AUTO_UPDATE=1 \
    "$@" \
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
}

launch_app "$IPHONE_UDID" \
  SIMCTL_CHILD_GRIMORA_SYNC_TEST_CREATE_LIST="iPhone Deck" \
  SIMCTL_CHILD_GRIMORA_SYNC_TEST_DEFAULT_SEARCH="type:artifact" \
  SIMCTL_CHILD_GRIMORA_SYNC_TEST_CURRENCY="AUD"
wait_for "iPhone creates its local list" list_exists "$IPHONE_UDID" "iPhone Deck"
IPHONE_LIST_ID="$(list_id "$IPHONE_UDID" "iPhone Deck")"
wait_for "iPhone uploads its list" relay_list_exists "iPhone Deck"

launch_app "$IPAD_UDID"
wait_for "iPad downloads the iPhone list" list_exists "$IPAD_UDID" "iPhone Deck"

launch_app "$IPAD_UDID" \
  SIMCTL_CHILD_GRIMORA_SYNC_TEST_CREATE_LIST="iPad Deck"
wait_for "iPad creates an independent list" list_exists "$IPAD_UDID" "iPad Deck"
wait_for "iPad uploads its independent list" relay_list_exists "iPad Deck"
launch_app "$IPHONE_UDID"
wait_for "iPhone merges the iPad list" list_exists "$IPHONE_UDID" "iPad Deck"

launch_app "$IPAD_UDID" \
  SIMCTL_CHILD_GRIMORA_SYNC_TEST_DELETE_LIST="iPhone Deck"
wait_for "iPad deletes the iPhone list" list_missing "$IPAD_UDID" "iPhone Deck"
wait_for "iPad uploads the deletion tombstone" relay_tombstone_exists "$IPHONE_LIST_ID"
launch_app "$IPHONE_UDID"
wait_for "iPhone receives the deletion tombstone" list_missing "$IPHONE_UDID" "iPhone Deck"

xcrun simctl terminate "$IPHONE_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$IPHONE_UDID" "$BUNDLE_ID"
xcrun simctl install "$IPHONE_UDID" "$APP_PATH"
mkdir -p "$(dirname "$(database_path "$IPHONE_UDID")")"
launch_app "$IPHONE_UDID"

wait_for "reinstalled iPhone restores the surviving iPad list" \
  list_exists "$IPHONE_UDID" "iPad Deck"
wait_for "reinstalled iPhone does not resurrect the deleted list" \
  list_missing "$IPHONE_UDID" "iPhone Deck"

PREFERENCES="$(container_path "$IPHONE_UDID")/Library/Preferences/$BUNDLE_ID.plist"
for _ in $(seq 1 80); do
  if [[ -f "$PREFERENCES" ]] \
    && /usr/libexec/PlistBuddy -c \
      "Print :Grimora.defaultSearch.text" "$PREFERENCES" 2>/dev/null \
      | grep -qx "type:artifact" \
    && /usr/libexec/PlistBuddy -c \
      "Print :Grimora.value.displayCurrency" "$PREFERENCES" 2>/dev/null \
      | grep -qx "AUD"; then
    printf 'PASS: reinstalled iPhone restores the default search\n'
    printf 'PASS: reinstalled iPhone restores the display currency\n'
    exit 0
  fi
  sleep 0.25
done

printf 'FAIL: reinstalled iPhone did not restore synced preferences\n' >&2
exit 1
