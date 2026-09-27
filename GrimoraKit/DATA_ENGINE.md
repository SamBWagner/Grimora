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

Oracle Tags provenance is split intentionally: semantic rows record the stable
`scryfall-oracle-tags@<updatedAt>` source identity, while `manifest.json` records
both `oracleTagsUpdatedAt` and the exact `oracleTagsDownloadURI`. The enrichment
stage consumes the local expanded JSONL file and does not retain a duplicate URI.
Enrichment version 2 filters tag memberships to Oracle-first catalog identities
before computing counts and IDF statistics. Validation keeps version 1 catalogs
readable, while version 2 requires every semantic card key to resolve locally.

## Incremental updates (delta chain)

Each build also publishes a consecutive `previous → this` **delta** so a client on
the prior build downloads only the change (typically a few MB) instead of the full
catalog artifact, patching its local catalog in place:

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

## Semantic publication evidence gate

`Tools/run_engine_tests.sh` is the deterministic offline engine gate. Its default
coverage includes the golden pipeline, engine build integration, manifest and
storage compatibility, logical digests, chain selection, semantic storage and
enrichment, delta round trips, publication-evidence fixtures, and the catalog API
route:

```text
Tools/run_engine_tests.sh
```

The private A→B→C publication harness is opt-in and never publishes its artifacts:

```text
GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR=/absolute/path/to/Builds/<version> \
GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR="$PWD/.hermes/artifacts/semantic-publication" \
GRIMORA_SEMANTIC_PUBLICATION_BASE_BUILD_SECONDS=<measured-seconds> \
Tools/run_engine_tests.sh --semantic-publication
```

Both directories must be nonempty when the harness is enabled. The script injects the
private `GRIMORA_SEMANTIC_PUBLICATION_ENABLED=1` gate only for an actual
`--semantic-publication` run, so inherited base/output variables do not activate the
real-base test under the default gate or a broad `swift test`. The base must be a
valid real engine build. Before any output cleanup, the harness expands
`catalog.sqlite.gz` into a project-local temporary validation directory and requires
its size and SHA-256 to match both `catalog.sqlite` and the manifest. The output must
be an empty project-local directory, or a prior directory carrying an exact regular,
non-symlink harness marker; overlapping paths and symlinks are rejected. With neither
path variable set, the opt-in command exits successfully without running private-data
work; partial or whitespace-only enabled configuration fails closed.

The harness copies the real build as A, creates deterministic controlled B and C
catalogs, builds and compresses A→B and B→C deltas, applies each transition and the
complete chain, and writes `report.json`. It verifies exact logical target digests,
strict manifest validation, SQLite integrity, semantic counts, duplicate/orphan
absence, and representative card/tag and recursive hierarchy queries.

### Private measurement — September 26, 2026

No artifact from this run was published. Build A was
`v1-b7526ec0b3a60bba764e`, with 118,389 cards and Oracle Tags enrichment version 2.
It contained 4,557 tags, 834 aliases, 4,542 hierarchy edges, 234,718 card-tag
memberships, and 4,557 statistics rows. A, B, C, both individual applications, and
the complete chain all passed strict manifest validation and `PRAGMA quick_check`;
all measured duplicate and orphan counts were zero.

| Artifact | Uncompressed bytes | Compressed bytes | Build/apply time |
| --- | ---: | ---: | ---: |
| A full catalog | 605,990,912 | 151,613,905 | 1,255.920 s build |
| B controlled catalog | 605,818,880 | 151,610,857 | 75.064 s generation |
| C controlled catalog | 605,818,880 | 151,611,530 | 74.837 s generation |
| A→B delta | 34,926,592 | 6,001,398 | 5.519 s build / 1.820 s apply |
| B→C delta | 34,926,592 | 6,000,981 | 5.637 s build / 1.845 s apply |

Each compressed semantic delta was 3.958% of its target full compressed catalog;
the complete A→B→C apply took 3.383 seconds. This is well below the full-download
decision threshold, so format 2's validated whole-semantic-snapshot replacement is
retained rather than redesigned.

The comparable non-semantic build `v1-a6fe02d65d4a4b76cc2e` used the same Scryfall
and MTGJSON snapshots. Semantic enrichment increased the full catalog by 108,589,056
uncompressed bytes (21.831%) and 22,788,503 compressed bytes (17.689%). Logical
digest calculation took 11.587–11.596 seconds per full catalog. Representative
indexed semantic reads completed in 0.031–0.311 ms, including card→tag, tag→card,
ancestor, and descendant traversal.
