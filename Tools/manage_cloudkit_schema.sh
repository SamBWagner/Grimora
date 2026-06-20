#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="BJPQVZR5PZ"
CONTAINER_ID="iCloud.com.samwagner.Grimora"
SCHEMA_FILE="$ROOT_DIR/CloudKit/Grimora.ckdb"
EXPECTED_TYPES_FILE="$ROOT_DIR/CloudKit/expected-record-types.txt"
EXPECTED_FIELDS_FILE="$ROOT_DIR/CloudKit/expected-fields.txt"
EVIDENCE_ROOT="$ROOT_DIR/AppStoreBuilds/cloudkit"

usage() {
  cat <<'EOF'
Usage:
  Tools/manage_cloudkit_schema.sh status
  Tools/manage_cloudkit_schema.sh backup
  Tools/manage_cloudkit_schema.sh capture-development
  Tools/manage_cloudkit_schema.sh validate-development
  Tools/manage_cloudkit_schema.sh import-development
  Tools/manage_cloudkit_schema.sh promote-production

Before using authorized commands, save a CloudKit management token:
  xcrun cktool save-token --type management --method keychain

Production promotion additionally requires:
  GRIMORA_CONFIRM_PRODUCTION_SCHEMA=YES
EOF
}

require_schema_file() {
  if [[ ! -s "$SCHEMA_FILE" ]]; then
    echo "Missing canonical schema: $SCHEMA_FILE" >&2
    echo "Run capture-development after a debug build bootstraps development CloudKit." >&2
    exit 1
  fi
}

verify_schema_contract() {
  local schema_file="$1"
  local schema_text
  schema_text="$(strings "$schema_file")"

  for contract_file in "$EXPECTED_TYPES_FILE" "$EXPECTED_FIELDS_FILE"; do
    while IFS= read -r required_name; do
      [[ -z "$required_name" ]] && continue
      if ! grep -Fq "$required_name" <<<"$schema_text"; then
        echo "Schema is missing required contract name: $required_name" >&2
        exit 1
      fi
    done < "$contract_file"
  done
}

export_schema() {
  local environment="$1"
  local output_file="$2"
  mkdir -p "$(dirname "$output_file")"
  xcrun cktool export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment "$environment" \
    --output-file "$output_file"
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

case "${1:-}" in
  status)
    xcrun cktool get-teams
    ;;

  backup)
    evidence_dir="$EVIDENCE_ROOT/$timestamp"
    export_schema development "$evidence_dir/development.ckdb"
    export_schema production "$evidence_dir/production.ckdb"
    echo "Exported CloudKit schema evidence to $evidence_dir"
    ;;

  capture-development)
    export_schema development "$SCHEMA_FILE"
    verify_schema_contract "$SCHEMA_FILE"
    echo "Captured canonical development schema at $SCHEMA_FILE"
    ;;

  validate-development)
    require_schema_file
    verify_schema_contract "$SCHEMA_FILE"
    xcrun cktool validate-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment development \
      --file "$SCHEMA_FILE"
    ;;

  import-development)
    require_schema_file
    verify_schema_contract "$SCHEMA_FILE"
    xcrun cktool import-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment development \
      --validate \
      --file "$SCHEMA_FILE"
    ;;

  promote-production)
    require_schema_file
    verify_schema_contract "$SCHEMA_FILE"
    if [[ "${GRIMORA_CONFIRM_PRODUCTION_SCHEMA:-}" != "YES" ]]; then
      echo "Refusing production schema import without GRIMORA_CONFIRM_PRODUCTION_SCHEMA=YES" >&2
      exit 1
    fi

    evidence_dir="$EVIDENCE_ROOT/$timestamp"
    export_schema production "$evidence_dir/production-before.ckdb"
    xcrun cktool validate-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment production \
      --file "$SCHEMA_FILE"
    xcrun cktool import-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment production \
      --validate \
      --file "$SCHEMA_FILE"
    export_schema production "$evidence_dir/production-after.ckdb"
    verify_schema_contract "$evidence_dir/production-after.ckdb"
    echo "Production CloudKit schema imported and verified. Evidence: $evidence_dir"
    ;;

  *)
    usage
    exit 1
    ;;
esac
