# Grimora Data Engine

The Mac builds and enriches catalogs. Fly runs only `grimora-data-api`; private
Tigris storage holds immutable artifacts.

## Commands

```text
swift run --package-path GrimoraKit grimora-data-engine check
swift run --package-path GrimoraKit grimora-data-engine build [--force]
swift run --package-path GrimoraKit grimora-data-engine publish <artifact-or-build-directory>
swift run --package-path GrimoraKit grimora-data-engine run [--force]
swift run --package-path GrimoraKit grimora-data-engine status
```

Set `TIGRIS_ARTIFACTS_BUCKET`, `TIGRIS_METADATA_BUCKET`, and optionally
`TIGRIS_ENDPOINT`, `TIGRIS_REGION`, and `GRIMORA_CATALOG_PUBLIC_BASE_URL`.
The native Mac engine defaults to Tigris's public `https://t3.storage.dev`
endpoint. The Fly API uses the private Fly endpoint configured in
`fly.data-api.toml`.
Write credentials are read from
`TIGRIS_ACCESS_KEY_ID`/`TIGRIS_SECRET_ACCESS_KEY` or generic-password Keychain
items in service `com.samwagner.GrimoraDataEngine.tigris`, accounts
`access-key-id` and `secret-access-key`.

Install the six-hour, wake-coalescing LaunchAgent with:

```text
Tools/install_grimora_data_engine_launch_agent.sh
```

## API

The Fly API needs both bucket names and read-only credentials. Deploy with:

```text
flyctl deploy --config fly.data-api.toml
```

Configure a 90-day lifecycle expiry only on the artifacts bucket. The metadata
bucket retains `current.json` and `current/catalog.sqlite.gz` without expiry.
The engine intentionally does not receive list/delete permission.
