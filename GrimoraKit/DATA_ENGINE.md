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

## Incremental updates (delta chain)

Each build also publishes a consecutive `previous → this` **delta** so a client on
the prior build downloads only the change (typically ~1–3 MB) instead of the full
~126 MB artifact, patching its local catalog in place:

- The manifest carries per-build `contentDigests` (SHA-256 over logical row values,
  not file bytes — `VACUUM`/FTS make the file non-reproducible). The client verifies
  its patched catalog against these before staging; any mismatch → full download.
- Delta artifacts live at `catalogs/<version>/delta-from-<base>.sqlite.gz`
  (immutable, artifacts bucket). An ordered `chain.json` (metadata bucket, 60s cache,
  newest 30 builds) is served at `GET /v1/catalog/chain`; deltas resolve via
  `GET /v1/catalog/:version/delta/:base`.
- Delta generation is **best-effort**: it diffs against the previous build's
  `Builds/<prev>/catalog.sqlite`. That directory must not be pruned within the chain
  window (30 builds) or the chain breaks and clients fall back to a full download —
  correct, just less efficient. A `catalogSchemaVersion` bump also breaks the chain
  by design (one forced full download at rollout).
- A device several builds behind walks the whole chain, applying each consecutive
  delta in order (each delta reproduces its build exactly, so the working copy after
  step K is precisely the base the next delta was diffed against). If the deltas would
  together rival the full compressed artifact (or the path exceeds 30 steps), the
  client prefers a plain full download.
