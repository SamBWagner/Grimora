# Grimora Semantic Discovery and Deck Intelligence Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Evolve Grimora from its current local catalog and Scryfall-style search into an explainable semantic discovery system with card relationships, list recommendations, natural-language-to-Grimora-query translation, and an Obsidian-like deck graph.

**Release target:** Ship the complete roadmap together as Grimora 2.0 from `release/2.0`. The App Store version is currently 1.7; the unpublished `release/1.8` work is the starting point for 2.0, and there will be no separate 1.8 or 1.9 App Store release.

**Architecture:** Store a sparse, deterministic, Oracle-level graph of cards ↔ functional concepts rather than materializing all card-to-card pairs. Derive related cards, deck profiles, recommendations, and bounded deck subgraphs locally from that graph. Natural-language input must compile into a typed intent and then into existing validated Grimora syntax; it must never emit SQL or directly invent cards, rules, legality, or combos.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, SQLite/FTS5, Scryfall bulk JSONL, Grimora's existing catalog/delta pipeline, XCTest/XCUITest, SwiftUI `Canvas` for the graph, and a provider-neutral structured-generation interface for natural-language translation.

---

## 1. Product outcome and guardrails

The final user experience has four connected capabilities:

1. **Semantic card relationships** — users can search functional concepts and inspect why two cards are related.
2. **Recommendations for an existing list** — users can see themes, weakly connected cards, related candidates, and eventually deficit-aware swap suggestions.
3. **Natural-language card search** — users describe cards in ordinary language; Grimora previews a functional syntax query and executes it only through the existing parser/compiler.
4. **Deck graph** — users can inspect the semantic connections inside a list, including highly connected cards, clusters, and low-connection cards.

### Non-negotiable guardrails

- Work at **Oracle-card identity**, not printing identity. Use `o:<oracle_id>` and fall back to `p:<printing_id>` only when an Oracle ID is unavailable.
- Do not create an all-pairs card-edge table. The initial graph is a sparse bipartite card ↔ concept graph plus concept hierarchy.
- Do not use free-form model-generated tags as source-of-truth. Version 1 imports Scryfall Oracle tags and deterministic card facts only.
- Do not let a model emit SQL, table names, arbitrary fields, legality claims, card names, or combo claims.
- Do not silently reinterpret natural-language input. Show the generated Grimora query and assumptions before search.
- Do not initially add `.graph` to persisted `CardCollectionViewMode`; use a modal Insights surface to avoid archive, migration, sync, and existing UI-test churn.
- Do not add graph/recommendation endpoints to `GrimoraDataAPI`; keep the Linux redirect service thin and run discovery against the distributed local SQLite catalog.
- Do not publish a semantic catalog until digests, validation, and semantic delta round trips are complete.
- Do not describe a low-connection card as bad. Use language such as “few semantic links in this list” and explain the measured basis.
- Preserve existing search behavior. Natural-language search is an explicit **Describe cards** action, never automatic prose detection.

---

## 2. Current architecture and constraints

### Existing strengths

- `GrimoraKit/Sources/GrimoraDataPipeline/CatalogPipeline.swift` already defines `CatalogEnrichmentStage` and runs stages before catalog finalization.
- `GrimoraKit/Sources/GrimoraEngineKit/GrimoraDataEngine.swift` already builds, validates, compresses, versions, publishes, and records enrichment versions.
- `GrimoraKit/Sources/GrimoraCore/CardDatabase+Migrations.swift` owns SQLite DDL.
- `GrimoraKit/Sources/GrimoraCore/CardDatabase+CatalogStorage.swift` validates and attaches the distributed catalog.
- `GrimoraKit/Sources/GrimoraCore/CatalogContentDigest.swift` supplies deterministic logical digests.
- `GrimoraKit/Sources/GrimoraEngineKit/CatalogDeltaBuilder.swift` and `GrimoraKit/Sources/GrimoraCore/CatalogDeltaApplier.swift` provide the incremental chain.
- `ScryfallSyntaxFieldRegistry.swift` already recognizes `function:`, `otag:`, and `oracletag:` even though `SearchQueryCompiler.swift` currently rejects them offline.
- `CardCollectionDetailView.swift` is a shared cross-platform list-detail integration point.
- `CardDetailView.swift` is already the shared card-inspection surface.
- The app has a generated-query Advanced Search UI that can host a preview-only natural-language translator.

### Constraints to design around

- `GrimoraDataEngine.performBuild` currently constructs `CatalogPipeline()` with no enrichment stages.
- Enrichment-source identity is not part of `CatalogSourceVersions`; a tag update alone would not trigger a build.
- `CardDatabase.database` is internal to `GrimoraCore`; the pipeline needs public transactional semantic writer APIs rather than raw SQLite access.
- Attached catalogs can be shadowed by empty `main` tables unless every semantic catalog table is added to `catalogTablesToDropFromMain`.
- Existing content digests and deltas know nothing about semantic tables.
- Search compilation alone is not sufficient validation; translation must call `ScryfallSyntaxValidator.validate`, require `isSupportedOffline`, and compile successfully.
- A previous plain-text AI search feature was removed in commit `36bc4fe` after growing into a large input-mode/state/history system. This implementation must remain an explicit, preview-first action.
- Runtime UI changes require explicit macOS, iOS, iPadOS, and visionOS verification under `AGENTS.md`.

---

## 3. Target data model

The first production schema should stay deliberately small:

```sql
CREATE TABLE semantic_tags (
    id TEXT PRIMARY KEY,
    namespace TEXT NOT NULL,
    slug TEXT NOT NULL,
    label TEXT NOT NULL,
    description TEXT,
    similarity_enabled INTEGER NOT NULL DEFAULT 1,
    source TEXT NOT NULL,
    UNIQUE(source, slug)
);

CREATE TABLE semantic_tag_aliases (
    tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    alias_key TEXT NOT NULL,
    PRIMARY KEY(tag_id, alias_key)
);

CREATE TABLE semantic_tag_edges (
    parent_tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
    child_tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
    PRIMARY KEY(parent_tag_id, child_tag_id)
);

CREATE TABLE semantic_card_tags (
    card_key TEXT NOT NULL,
    tag_id TEXT NOT NULL REFERENCES semantic_tags(id) ON DELETE CASCADE,
    weight_millis INTEGER NOT NULL,
    annotation TEXT,
    source TEXT NOT NULL,
    PRIMARY KEY(card_key, tag_id, source)
);

CREATE TABLE semantic_tag_stats (
    tag_id TEXT PRIMARY KEY REFERENCES semantic_tags(id) ON DELETE CASCADE,
    direct_card_count INTEGER NOT NULL,
    effective_card_count INTEGER NOT NULL,
    idf_millis INTEGER NOT NULL
);
```

Indexes must support both directions:

```sql
CREATE INDEX idx_semantic_card_tags_tag_card
ON semantic_card_tags(tag_id, card_key);

CREATE INDEX idx_semantic_card_tags_card_tag
ON semantic_card_tags(card_key, tag_id);

CREATE INDEX idx_semantic_tag_aliases_key
ON semantic_tag_aliases(alias_key, tag_id);
```

### Representation decision to validate before locking schema

Benchmark these three hierarchy strategies with the current Scryfall snapshot and a 100-card list:

1. Recursive CTE over `semantic_tag_edges`.
2. Materialized tag-closure table.
3. Flattened effective card-feature rows with inherited depth/weight.

Choose the smallest representation that meets the measured on-device budgets. Do not add both a closure table and flattened features pre-emptively.

#### Measured decision — 2026-09-23

`SemanticStorageBenchmarkTests` expands the checked, source-dated semantic fixture into a deterministic 100-card Oracle-profile deck and proves recursive, closure, and flattened layouts return identical feature vectors, functional-tag matches, related-card ordering, deck profiles, and induced graphs. Fifty-query averages from a macOS arm64 debug run were:

| Layout | SQLite bytes | Import | Related | Function search | Deck profile | Induced graph |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Recursive edges | 241,664 | 9.9817 ms | 2.9327 ms | 2.0916 ms | 2.3182 ms | 29.6221 ms |
| Materialized closure | 278,528 | 9.1185 ms | 1.4198 ms | 0.8830 ms | 1.1181 ms | 28.4853 ms |
| Flattened features | 589,824 | 12.5621 ms | 0.4220 ms | 0.0351 ms | 0.3681 ms | 25.4137 ms |

Select **recursive CTE traversal over direct `semantic_tag_edges` and `semantic_card_tags`**. It is the smallest representation, all measured operations remain comfortably inside the Phase 0 latency budgets, and it avoids publishing redundant closure or effective-feature rows before profiling real device catalogs. Keep full card-to-card materialisation deferred.

### Weighting policy

- Preserve Scryfall's raw tagging weight, normalized to deterministic fixed-point integers.
- Preserve direct memberships and tag hierarchy separately.
- Apply hierarchy depth decay only when computing an effective feature vector.
- Multiply effective feature weights by global inverse frequency so broad tags contribute less.
- Set `similarity_enabled = 0` for metadata/trivia branches such as cycles, card-name properties, storyline references, and alliteration.
- Keep exact weight constants in one versioned policy type and record that policy version in the manifest enrichment identity.

---

## 4. Integrated 2.0 delivery map

| Milestone | User value | Depends on | Explicitly deferred |
|---|---|---|---|
| **A. Functional tag search** | Search `function:`/`otag:` offline and see functional tags on card detail | Semantic catalog, digest, delta | Related-card scoring, graph, NLP |
| **B. Related cards** | Open a card and browse explainable nearest functional neighbours | A | Deck diagnosis and swaps |
| **C. List insights** | See dominant themes, connected cards, low-connection cards, and read-only recommendations | B | Visual graph and deficit diagnosis |
| **D. Deck graph** | Visualize card clusters and inspect why nodes connect | C | Editable graph and persisted graph mode |
| **E. Natural-language search preview** | Describe cards, inspect generated Grimora syntax, then confirm search | A and typed translator contract | Automatic execution, synced prompt history |
| **F. Deficit-aware recommendations** | Explain what a list over/under-supplies and suggest additions/cuts that improve it | C plus role/conversion ontology | Unverified combos and autonomous deck editing |
| **G. Natural-language deck advisor** | Convert “this deck is slow” into measured diagnosis and constrained swap goals | F plus the NLP contract | Unreviewed model advice |

Each milestone is independently verifiable but is not an App Store release. All milestones accumulate on `release/2.0`; do not ship 2.0 until the full roadmap through natural-language search and deck advice meets its quality, performance, migration, and four-platform gates.

---

# Phase 0 — Lock the semantic contract with a non-production spike

### Task 1: Add a checked-in semantic benchmark corpus

**Objective:** Turn the successful Sythis experiment into repeatable quality evidence before choosing production schema details.

**Files:**
- Create: `GrimoraKit/Tests/GrimoraCoreTests/Fixtures/SemanticCards.json`
- Create: `GrimoraKit/Tests/GrimoraCoreTests/Fixtures/SemanticTags.json`
- Create: `GrimoraKit/Tests/GrimoraCoreTests/SemanticRelationshipBenchmarkTests.swift`
- Modify: `GrimoraKit/Package.swift` to copy the fixture directory if the existing test-resource declaration does not already include it.

**Steps:**

1. Check in a bounded, source-dated fixture containing Sythis, enchantress analogues, near analogues such as Beast Whisperer, and deliberately unrelated cards.
2. Include direct tag IDs, labels, hierarchy, weight, and metadata tags that must be excluded.
3. Write failing tests asserting:
   - Satyr Enchanter and Enchantress's Presence outrank broad draw engines for Sythis.
   - `alliteration` and cycle tags make zero similarity contribution.
   - reprints collapse to one Oracle identity.
   - score explanations list the strongest shared functional concepts.
4. Implement only a test-local prototype scorer.
5. Record benchmark expectations as ranked groups rather than one brittle total order where ties are legitimate.
6. Run:
   ```bash
   swift test --package-path GrimoraKit --filter SemanticRelationshipBenchmarkTests
   ```
7. Commit:
   ```bash
   git add GrimoraKit/Package.swift GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "test: add semantic relationship benchmark corpus"
   ```

**Exit gate:** The benchmark catches the known free-form-tagging failure modes and reproduces the useful Sythis neighbourhood without network access.

### Task 2: Benchmark the hierarchy storage choices

**Objective:** Choose recursive hierarchy traversal, closure rows, or flattened effective features using evidence rather than preference.

**Files:**
- Create: `GrimoraKit/Tests/GrimoraCoreTests/SemanticStorageBenchmarkTests.swift`
- Create: `GrimoraKit/SEMANTIC_DISCOVERY.md`

**Steps:**

1. Load a representative local snapshot into temporary SQLite databases using each of the three candidate layouts.
2. Measure database bytes, import time, single-card related lookup, functional-tag search, 100-card deck profile, and 100-card induced graph construction.
3. Verify all three produce identical semantic results before comparing speed.
4. Record the chosen layout and rejected alternatives in `SEMANTIC_DISCOVERY.md`.
5. Define provisional budgets from the slowest supported device/simulator baseline; do not invent a release threshold before measurement.
6. Run the focused benchmark manually, then keep correctness assertions in normal CI while performance measurements remain opt-in.
7. Commit:
   ```bash
   git add GrimoraKit/SEMANTIC_DISCOVERY.md GrimoraKit/Tests/GrimoraCoreTests/SemanticStorageBenchmarkTests.swift
   git commit -m "docs: choose semantic graph storage layout"
   ```

**Exit gate:** One representation is selected, documented, and shown to scale to a 100-card deck without an all-pairs table.

---

# Phase 1 — Build and distribute the semantic catalog safely

> **Release rule:** No engine publish occurs until Tasks 3–9 all pass. Intermediate code may exist on a feature branch, but it must not produce a production catalog whose semantic tables are absent from validation, digests, or deltas.

### Task 3: Add semantic models and Oracle identity helpers

**Objective:** Define stable Core types shared by ingestion, querying, recommendations, and graph presentation.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraCore/CardSemanticModels.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/CardSemanticModelsTests.swift`
- Reuse: `GrimoraKit/Sources/GrimoraCore/CardCollectionRulesetValidation.swift`

**Required types:**

```swift
public struct CardSemanticKey: Hashable, Codable, Sendable {
  public var rawValue: String
}

public struct CardSemanticTag: Identifiable, Equatable, Sendable {
  public var id: String
  public var slug: String
  public var label: String
  public var description: String?
  public var similarityEnabled: Bool
}

public struct CardSemanticMembership: Equatable, Sendable {
  public var cardKey: CardSemanticKey
  public var tagID: String
  public var weightMillis: Int
  public var annotation: String?
  public var source: String
}
```

**Steps:**

1. Write tests for `o:<oracle_id>` identity and `p:<printing_id>` fallback.
2. Make normalization stable and case-insensitive where identifiers require it.
3. Reuse the same Oracle-first identity rule used by Commander singleton validation.
4. Keep UI presentation and SQLite details out of these models.
5. Run:
   ```bash
   swift test --package-path GrimoraKit --filter CardSemanticModelsTests
   ```
6. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore/CardSemanticModels.swift GrimoraKit/Tests/GrimoraCoreTests/CardSemanticModelsTests.swift
   git commit -m "feat: define semantic card models"
   ```

### Task 4: Add dark semantic schema and legacy-safe read/write APIs

**Objective:** Add semantic storage without activating ingestion and prove legacy/attached catalogs remain correct.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraCore/CardDatabase+Migrations.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CardDatabase+CatalogStorage.swift`
- Create: `GrimoraKit/Sources/GrimoraCore/CardDatabase+Semantics.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/CardDatabaseSemanticsTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraCoreTests/CatalogStorageTests.swift`

**Steps:**

1. Write failing migration tests for all chosen tables, foreign keys, uniqueness, and indexes.
2. Add every distributed semantic table to `catalogTablesToDropFromMain` so `main` cannot shadow the attached catalog.
3. Add a public transactional writer API that replaces one complete semantic snapshot; do not expose `SQLiteDatabase` publicly.
4. Add read APIs for direct tags, aliases, hierarchy, and tag statistics.
5. Treat absent semantic tables in a legacy catalog as “semantics unavailable,” not a fatal open error.
6. Test rollback on malformed tags, orphan edges, duplicate memberships, and interrupted replacement.
7. Run:
   ```bash
   swift test --package-path GrimoraKit --filter CardDatabaseSemanticsTests
   swift test --package-path GrimoraKit --filter CatalogStorageTests
   ```
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore/CardDatabase+Migrations.swift \
     GrimoraKit/Sources/GrimoraCore/CardDatabase+CatalogStorage.swift \
     GrimoraKit/Sources/GrimoraCore/CardDatabase+Semantics.swift \
     GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "feat: add semantic catalog storage"
   ```

### Task 5: Fetch and cache Scryfall Oracle Tags as a versioned source

**Objective:** Make Oracle Tags a first-class build input whose updates independently trigger catalog builds.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraCore/BulkDataManifest.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CatalogManifest.swift`
- Modify: `GrimoraKit/Sources/GrimoraDataPipeline/CatalogPipeline.swift`
- Modify: `GrimoraKit/Sources/GrimoraEngineKit/GrimoraDataEngine.swift`
- Create: `GrimoraKit/Sources/GrimoraDataPipeline/ScryfallOracleTagDTO.swift`
- Create: `GrimoraKit/Sources/GrimoraDataPipeline/ScryfallOracleTagStreamScanner.swift`
- Test: `GrimoraKit/Tests/GrimoraDataPipelineTests/ScryfallOracleTagStreamScannerTests.swift`
- Fixture: `GrimoraKit/Tests/GrimoraDataPipelineTests/Fixtures/oracle-tags-sample.jsonl`

**Steps:**

1. Extend `BulkDataClient` with a generic typed-manifest lookup or a dedicated `fetchOracleTagsManifest`; retain current default-card behavior.
2. Add optional Oracle-tag update/source fields to `CatalogSourceVersions` so old manifests still decode.
3. Add the decompressed Oracle-tag JSONL URL to `CatalogBuildInputs`.
4. Cache the gzipped source under the existing source-version directory, expand atomically, and never treat a partial file as complete.
5. Decode IDs, slugs, labels, descriptions, aliases, parent/child IDs, taggings, weights, and annotations.
6. Add download progress text for Oracle Tags.
7. Verify an Oracle-tag-only source change makes `checkForUpdate` report a change.
8. Run:
   ```bash
   swift test --package-path GrimoraKit --filter ScryfallOracleTagStreamScannerTests
   swift test --package-path GrimoraKit --filter EngineRuntimeTests
   ```
9. Commit:
   ```bash
   git add GrimoraKit/Sources GrimoraKit/Tests/GrimoraDataPipelineTests
   git commit -m "feat: add Oracle Tags build input"
   ```

### Task 6: Implement deterministic Scryfall semantic enrichment

**Objective:** Populate the semantic graph through the existing enrichment protocol.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraDataPipeline/ScryfallOracleTagsEnrichment.swift`
- Modify: `GrimoraKit/Sources/GrimoraDataPipeline/CatalogPipeline.swift`
- Modify: `GrimoraKit/Sources/GrimoraEngineKit/GrimoraDataEngine.swift`
- Test: `GrimoraKit/Tests/GrimoraDataPipelineTests/ScryfallOracleTagsEnrichmentTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraDataPipelineTests/CatalogGoldenPipelineTests.swift`

**Steps:**

1. Write a failing test that imports the bounded fixture and asserts exact tag, alias, edge, membership, and stats rows.
2. Map Scryfall weights to fixed-point integers in one versioned policy.
3. Build Oracle membership keys without duplicating memberships across printings.
4. Mark known metadata branches as disabled using tag identity/hierarchy rules recorded in `SEMANTIC_DISCOVERY.md`.
5. Compute deterministic tag counts and fixed-point IDF statistics.
6. Initialize `ScryfallOracleTagsEnrichment` with the input URL and inject it into `CatalogPipeline` from the engine.
7. Include the enrichment identifier, policy version, and source digest in catalog identity.
8. Update the golden fixture only after reviewing the human-readable semantic rows.
9. Run:
   ```bash
   swift test --package-path GrimoraKit --filter ScryfallOracleTagsEnrichmentTests
   swift test --package-path GrimoraKit --filter CatalogGoldenPipelineTests
   swift test --package-path GrimoraKit --filter EngineBuildIntegrationTests
   ```
10. Commit:
   ```bash
   git add GrimoraKit/Sources GrimoraKit/Tests/GrimoraDataPipelineTests
   git commit -m "feat: enrich catalogs with Oracle Tags"
   ```

### Task 7: Extend catalog validation, counts, and logical digests

**Objective:** Make missing, stale, or corrupt semantic data detectable before publish and after client installation.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraCore/CatalogManifest.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CatalogContentDigest.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CardDatabase+CatalogStorage.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CardDatabase+CatalogBuild.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/CatalogContentDigestTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraCoreTests/CatalogStorageTests.swift`

**Steps:**

1. Add optional nested semantic counts/digests so older manifests remain decodable.
2. Hash semantic tables in canonical primary-key order.
3. Validate required tables, non-empty tags/memberships, no orphan taggings, no orphan edges, valid weight ranges, and manifest counts.
4. Bump `CatalogManifest.currentSchemaVersion` for the distributed schema change.
5. Verify legacy manifests without semantic digests retain their old digest scope.
6. Verify one membership change changes only the semantic digest and overall digest.
7. Run:
   ```bash
   swift test --package-path GrimoraKit --filter CatalogContentDigestTests
   swift test --package-path GrimoraKit --filter CatalogStorageTests
   swift test --package-path GrimoraKit --filter CatalogChainTests
   ```
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "feat: validate semantic catalog content"
   ```

### Task 8: Add semantic delta generation and transactional apply

**Objective:** Preserve normal incremental updates after semantic activation.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraCore/CatalogDeltaSchema.swift`
- Modify: `GrimoraKit/Sources/GrimoraEngineKit/CatalogDeltaBuilder.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CatalogDeltaApplier.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/CatalogChain.swift`
- Modify: `GrimoraKit/Sources/GrimoraEngineKit/GrimoraDataEngine.swift`
- Extend: `GrimoraKit/Tests/GrimoraDataEngineTests/CatalogDeltaRoundTripTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraDataEngineTests/RealDeltaValidationTests.swift`

**Steps:**

1. Add explicit semantic tag, alias, edge, membership, and stats upsert/delete tables to the patch schema.
2. Diff every semantic table deterministically.
3. Apply deletes in foreign-key-safe order and upserts in dependency order inside the existing transaction.
4. Bump `CatalogDelta.currentFormatVersion`.
5. Add tests for tag add/delete/rename, alias changes, hierarchy changes, membership add/delete/weight changes, and stats changes.
6. Verify A→B and A→B→C chains reproduce semantic and overall target digests exactly.
7. Make semantic-delta failures visible in engine logs; do not silently advertise an incomplete delta.
8. Verify unsupported schema/format clients fall back before applying.
9. Run:
   ```bash
   swift test --package-path GrimoraKit --filter CatalogDeltaRoundTripTests
   swift test --package-path GrimoraKit --filter RealDeltaValidationTests
   swift test --package-path GrimoraKit --filter CatalogChainTests
   ```
10. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Sources/GrimoraEngineKit \
     GrimoraKit/Tests/GrimoraDataEngineTests GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "feat: include semantic data in catalog deltas"
   ```

### Task 9: Expand the engine regression gate and perform a private full build

**Objective:** Prove the production artifact is internally consistent before any user-facing semantic feature or catalog publish.

**Files:**
- Modify: `Tools/run_engine_tests.sh`
- Modify: `GrimoraKit/DATA_ENGINE.md`
- Test: existing Core, Pipeline, Engine, and API targets.

**Steps:**

1. Expand the offline engine script to include digest, chain, delta-round-trip, semantic storage, semantic enrichment, and API route coverage.
2. Run all package tests:
   ```bash
   swift test --package-path GrimoraKit
   ```
3. Run the expanded engine gate:
   ```bash
   Tools/run_engine_tests.sh
   ```
4. Run live lightweight checks:
   ```bash
   Tools/run_engine_tests.sh --live
   ```
5. Build a full catalog without publishing:
   ```bash
   Tools/run_engine_tests.sh --full
   swift run --package-path GrimoraKit grimora-data-engine build --force
   ```
6. Inspect actual counts, sizes, timings, semantic table integrity, related-card benchmark results, and delta size.
7. Confirm an old catalog opens and a new catalog installs through both full and delta paths.
8. Record measured artifact growth and query performance in `GrimoraKit/SEMANTIC_DISCOVERY.md`.
9. Commit:
   ```bash
   git add Tools/run_engine_tests.sh GrimoraKit/DATA_ENGINE.md GrimoraKit/SEMANTIC_DISCOVERY.md
   git commit -m "test: gate semantic catalog publishing"
   ```

**Phase 1 exit gate:** The catalog graph is deterministic, fully validated, digest-covered, delta-covered, and measurable. Only now may a semantic catalog be published.

---

# Phase 2 — Ship functional search and visible tag provenance

### Task 10: Compile `function:` and `otag:` into offline semantic search

**Objective:** Deliver the first direct user value from the semantic catalog through existing search syntax.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraCore/SearchQueryCompiler.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/ScryfallSyntaxValidator.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/ScryfallSyntaxHighlighter.swift`
- Possibly modify: `GrimoraKit/Sources/GrimoraCore/ScryfallSyntaxFieldRegistry.swift`
- Extend: `GrimoraKit/Tests/GrimoraCoreTests/SearchQueryTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraCoreTests/SearchAndSyntaxCoverageTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraCoreTests/CardDatabaseSearchCoverageTests.swift`

**Steps:**

1. Write failing tests for `function:draw`, `otag:draw-engine`, `oracletag:"repeatable lifegain"`, negation, AND, OR, and unknown tags.
2. Resolve slug, label, and aliases through semantic tables.
3. Compile semantic terms to bound `EXISTS` queries; never concatenate tag values into SQL.
4. Implement documented hierarchy behavior using the representation selected in Task 2.
5. Keep `art:`, `atag:`, and `arttag:` unsupported until an illustration-tag source is deliberately added.
6. Fix syntax highlighting so valid-but-offline-unsupported clauses do not appear executable.
7. Bump `CardDatabase.currentSearchSchemaVersion` only if readiness must require semantic search support.
8. Verify result IDs against fixtures, not merely successful parsing.
9. Run:
   ```bash
   swift test --package-path GrimoraKit --filter SearchQueryTests
   swift test --package-path GrimoraKit --filter SearchAndSyntaxCoverageTests
   swift test --package-path GrimoraKit --filter CardDatabaseSearchCoverageTests
   ```
10. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "feat: support offline functional tag search"
   ```

### Task 11: Show functional tags on card detail

**Objective:** Make the new data understandable and give users one-tap semantic searches.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/CardDetailSemanticSection.swift`
- Create: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+SemanticDiscovery.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardDetailView.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/GrimoraEnvironment.swift`
- Extend: `GrimoraKit/Tests/GrimoraUITests/GrimoraAppModelTests.swift`
- Create: `GrimoraCrossPlatformUITests/SemanticTagUITests.swift`

**Steps:**

1. Load tags asynchronously by semantic card key with stale-card cancellation protection.
2. Add a compact “Functions” section containing gameplay-enabled tags only.
3. Show source/provenance in an info affordance; do not imply Grimora authored Scryfall community tags.
4. Tapping a tag submits `otag:<slug>` through the existing search execution path.
5. Show no section for legacy catalogs or cards without semantics.
6. Add accessibility labels for tag name, source, and action.
7. Run focused model tests and cross-platform UI tests.
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests \
     GrimoraCrossPlatformUITests/SemanticTagUITests.swift
   git commit -m "feat: show functional tags in card detail"
   ```

**Milestone A exit gate:** Users can search functional concepts offline, inspect card tags, and jump from a tag to results on every supported platform.

---

# Phase 3 — Deliver explainable card-to-card relationships

### Task 12: Add deterministic related-card query APIs

**Objective:** Derive bounded nearest neighbours from shared semantic concepts without global pair materialization.

**Files:**
- Extend: `GrimoraKit/Sources/GrimoraCore/CardSemanticModels.swift`
- Extend: `GrimoraKit/Sources/GrimoraCore/CardDatabase+Semantics.swift`
- Create: `GrimoraKit/Sources/GrimoraCore/CardSemanticSimilarity.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/CardSemanticSimilarityTests.swift`

**Required result model:**

```swift
public struct RelatedCardResult: Identifiable, Equatable, Sendable {
  public var id: CardSemanticKey
  public var representativeCard: CardRecord
  public var scoreMillis: Int
  public var sharedConcepts: [CardSemanticContribution]
}
```

**Steps:**

1. Write failing tests for hierarchy-aware weighted similarity, disabled tags, deterministic ties, Oracle deduplication, and representative-printing selection.
2. Retrieve candidates via shared enabled tags and cap candidate count before scoring.
3. Score in a pure Core type using the one versioned policy.
4. Return the strongest shared concepts as explanation evidence.
5. Add filters for paper availability, format legality, and optional colour identity; keep them explicit query options.
6. Benchmark Sythis and the checked-in corpus.
7. Run:
   ```bash
   swift test --package-path GrimoraKit --filter CardSemanticSimilarityTests
   swift test --package-path GrimoraKit --filter SemanticRelationshipBenchmarkTests
   ```
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "feat: add explainable related-card queries"
   ```

### Task 13: Add a Related Cards section to card detail

**Objective:** Let users browse the graph one card at a time before introducing deck-level complexity.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/CardDetailRelatedCardsSection.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardDetailView.swift`
- Extend: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+SemanticDiscovery.swift`
- Extend: `GrimoraKit/Tests/GrimoraUITests/GrimoraAppModelTests.swift`
- Extend: `GrimoraCrossPlatformUITests/SemanticTagUITests.swift`

**Steps:**

1. Add an async related-card load keyed by selected semantic identity.
2. Render a bounded horizontal/list section with name, image, score band, and top two shared concepts.
3. Selecting a result reuses the existing `model.selectCard`/card-detail path.
4. Add “Why related?” disclosure instead of exposing an unexplained number by default.
5. Preserve loading, unavailable, empty, and error states separately.
6. Verify fast card switching cannot publish stale related results.
7. Verify macOS inspector, iPhone sheet, iPad layout, and visionOS presentation.
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests \
     GrimoraCrossPlatformUITests/SemanticTagUITests.swift
   git commit -m "feat: browse related cards"
   ```

**Milestone B exit gate:** A user can traverse explainable card relationships locally, with deterministic quality evidence and no all-pairs artifact.

---

# Phase 4 — Build list profiles and recommendations

### Task 14: Compute a pure semantic list snapshot

**Objective:** Convert a hydrated list into themes, card connectivity, and candidate evidence without UI or model dependencies.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraCore/CardCollectionSemanticProfile.swift`
- Create: `GrimoraKit/Sources/GrimoraCore/CardDatabase+CollectionSemantics.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/CardCollectionSemanticProfileTests.swift`

**Snapshot contents:**

- unique Oracle-level list nodes;
- coverage count and cards skipped for missing semantics;
- dominant concepts with support counts and weighted importance;
- bounded pairwise edges for cards in the list;
- weighted degree per card;
- low-connection cards with explicit evidence;
- recommendation candidates absent from the list;
- query policy and semantic data version.

**Steps:**

1. Collapse alternate printings and ignore quantities for semantic presence.
2. Include active deck zones by policy; keep sideboard/maybeboard handling explicit.
3. Compute concept importance as deck coverage × global specificity × concept-kind weight.
4. Compute only list-internal pairs, which is bounded for normal 60/100-card lists.
5. Classify connectivity from measured list-relative distributions; do not hard-code a universal “bad card” threshold.
6. Generate recommendation candidates from the list's important concepts and exclude cards already present.
7. For Commander lists, enforce legality, colour identity, and singleton rules before returning a candidate.
8. Return explanations containing matched concepts and supporting list cards.
9. Test empty, one-card, all-isolated, missing-card, duplicate-printing, 60-card, and Commander fixtures.
10. Run:
    ```bash
    swift test --package-path GrimoraKit --filter CardCollectionSemanticProfileTests
    ```
11. Commit:
    ```bash
    git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests/CardCollectionSemanticProfileTests.swift
    git commit -m "feat: profile list semantics"
    ```

### Task 15: Add a read-only List Insights sheet

**Objective:** Ship deck-level value before recommendations can mutate a list or a graph can render.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+CollectionInsights.swift`
- Create: `GrimoraKit/Sources/GrimoraUI/CardCollectionInsightsView.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardCollectionDetailView.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardCollectionDetailHeader.swift`
- Extend: `GrimoraKit/Tests/GrimoraUITests/GrimoraAppModelTests.swift`
- Create: `GrimoraCrossPlatformUITests/CollectionInsightsUITests.swift`

**Steps:**

1. Add an **Insights** action to macOS, touch, and visionOS list menus; hide it for transient/system lists initially.
2. Load a snapshot asynchronously with selected-list cancellation protection.
3. Show coverage, dominant themes, most-connected cards, and “few semantic links” cards.
4. Explain every classification with the exact shared concepts/support counts.
5. Provide list and accessibility representations before any Canvas graph.
6. Keep recommendations visible but read-only in this task.
7. Verify no usable semantics produces an honest catalog-update/empty state.
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests \
     GrimoraCrossPlatformUITests/CollectionInsightsUITests.swift
   git commit -m "feat: add semantic list insights"
   ```

### Task 16: Add recommendation actions and replacement context

**Objective:** Turn explainable recommendation candidates into safe, user-approved list changes.

**Files:**
- Extend: `GrimoraKit/Sources/GrimoraCore/CardCollectionSemanticProfile.swift`
- Extend: `GrimoraKit/Sources/GrimoraUI/CardCollectionInsightsView.swift`
- Extend: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+CollectionInsights.swift`
- Extend: `GrimoraKit/Tests/GrimoraCoreTests/CardCollectionSemanticProfileTests.swift`
- Extend: `GrimoraKit/Tests/GrimoraUITests/GrimoraAppModelTests.swift`
- Extend: `GrimoraCrossPlatformUITests/CollectionInsightsUITests.swift`

**Steps:**

1. Split recommendations into:
   - “More cards matching this list”;
   - “Cards similar to a selected card”;
   - later, deficit-aware changes.
2. Add a safe **Add** action that uses existing list mutation APIs and existing Commander duplicate confirmation behavior.
3. After an add, reload the snapshot and remove the card from candidates.
4. Offer likely cut context only as an explanation; do not perform a swap automatically.
5. Preserve the user's selected printing/finish flow when adding.
6. Verify legality, colour identity, duplicates, missing records, stale loads, and list count changes.
7. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Sources/GrimoraUI \
     GrimoraKit/Tests GrimoraCrossPlatformUITests
   git commit -m "feat: add explainable list recommendations"
   ```

**Milestone C exit gate:** Users get useful list analysis and safe recommendations even if the visual graph and natural-language features are not ready.

---

# Phase 5 — Add the Obsidian-like deck graph

### Task 17: Implement a deterministic, testable graph layout

**Objective:** Separate layout mathematics from SwiftUI rendering and ensure stable, bounded output.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/CardCollectionGraphLayout.swift`
- Test: `GrimoraKit/Tests/GrimoraUITests/CardCollectionGraphLayoutTests.swift`

**Steps:**

1. Define pure input/output models using stable semantic node IDs.
2. Implement a deterministic seeded force layout or choose another documented deterministic layout based on the benchmark.
3. Size nodes by weighted degree and weight edges by semantic similarity.
4. Prune visual edges separately from analytical degree; retain top-N edges per node and a global cap.
5. Fit finite positions into arbitrary viewport bounds.
6. Test empty, singleton, all-isolated, clustered, and 100-node inputs.
7. Assert identical input produces identical positions and edge selection.
8. Run:
   ```bash
   swift test --package-path GrimoraKit --filter CardCollectionGraphLayoutTests
   ```
9. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI/CardCollectionGraphLayout.swift \
     GrimoraKit/Tests/GrimoraUITests/CardCollectionGraphLayoutTests.swift
   git commit -m "feat: add deterministic deck graph layout"
   ```

### Task 18: Render a read-only graph inside List Insights

**Objective:** Visualize semantic clusters and low-connection cards without changing persisted list view modes.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/CardCollectionGraphView.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardCollectionInsightsView.swift`
- Extend: `GrimoraCrossPlatformUITests/CollectionInsightsUITests.swift`
- Add screenshot coverage under existing cross-platform screenshot conventions.

**Steps:**

1. Add Summary, Recommendations, and Graph sections/tabs inside the Insights sheet.
2. Render edges and nodes with `Canvas`, but add real overlay controls or an equivalent accessibility list for every interactive node.
3. Use a clear legend for node size, edge strength, and low-connection treatment.
4. Add identifiers:
   - `card-collection-insights`;
   - `card-collection-graph`;
   - `graph-node-<semantic-key>`;
   - `graph-connected-summary`;
   - `graph-low-connection-summary`.
5. Provide zoom/pan only after the fitted static graph is usable; do not make gesture complexity a release blocker.
6. Add honest empty, partial-coverage, and all-isolated states.
7. Capture and inspect compact iPhone, iPad landscape, macOS, and visionOS screenshots.
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraCrossPlatformUITests
   git commit -m "feat: visualize deck semantic connections"
   ```

### Task 19: Add graph-to-card interaction

**Objective:** Make the graph a discovery surface rather than a static diagram.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraUI/CardCollectionGraphView.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardCollectionInsightsView.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/CardCollectionDetailView.swift`
- Extend: relevant UI tests.

**Steps:**

1. Selecting a node highlights it and its strongest edges.
2. Show the top shared concepts for each highlighted neighbour.
3. Add **View Card**, reusing the existing card-detail selection path.
4. Let a recommended card open the same detail surface before adding.
5. Verify navigation/presentation independently on macOS, iPhone, iPad, and visionOS.
6. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests GrimoraCrossPlatformUITests
   git commit -m "feat: inspect cards from the deck graph"
   ```

**Milestone D exit gate:** The graph is deterministic, bounded, accessible, cross-platform, and backed by the same explainable snapshot as textual insights.

---

# Phase 6 — Build natural-language-to-Grimora search safely

### Task 20: Define a typed search-intent contract and serializer

**Objective:** Create a model-independent boundary that can only express supported Grimora search operations.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraCore/NaturalLanguageSearchIntent.swift`
- Create: `GrimoraKit/Sources/GrimoraCore/NaturalLanguageSearchTranslationPolicy.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/NaturalLanguageSearchTranslationPolicyTests.swift`
- Modify: `GrimoraKit/Sources/GrimoraCore/ScryfallSyntaxValidator.swift` only where validation gaps are proven.

**Version 1 typed fields:**

- copied name text;
- type;
- oracle text;
- keyword;
- color/color identity;
- mana value;
- rarity;
- format legality;
- functional tag.

Version 1 supports AND and negation only. OR, regex, prices, dates, sort/display directives, and `label:` remain deferred.

**Steps:**

1. Define enums for field, operator, grouping, and copied/resolved values.
2. Serialize typed clauses into canonical Grimora syntax.
3. Validate output using all of:
   - non-empty intent;
   - allowed field/operator/value policy;
   - `ScryfallSyntaxValidator.validate(query).isValidScryfall`;
   - `isSupportedOffline`;
   - successful `SearchQuery.compile`;
   - a meaningful predicate, not a compiler-accepted no-op.
4. Reject introduced proper nouns unless copied from input or resolved from local metadata.
5. Forbid `label:` in catalog context and permit it only in a later list-search policy.
6. Add adversarial tests for SQL-like text, unknown fields, invalid values, unsupported display terms, regex, and empty/no-op output.
7. Run:
   ```bash
   swift test --package-path GrimoraKit --filter NaturalLanguageSearchTranslationPolicyTests
   ```
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests/NaturalLanguageSearchTranslationPolicyTests.swift
   git commit -m "feat: define safe natural-language search intent"
   ```

### Task 21: Choose and abstract the translation provider

**Objective:** Make a deliberate cross-platform product decision instead of coupling app behavior or schema to Ollama/Foundation Models.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/NaturalLanguageSearchTranslating.swift`
- Create: `GrimoraKit/Sources/GrimoraUI/NaturalLanguageSearchAvailability.swift`
- Create: `GrimoraKit/Tests/GrimoraUITests/NaturalLanguageSearchProviderTests.swift`
- Update: `GrimoraKit/SEMANTIC_DISCOVERY.md`

**Provider decision matrix:**

- Apple on-device structured generation where available;
- a remote service only with explicit privacy, cost, auth, and availability design;
- Ollama as a development/test adapter, not an App Store runtime assumption;
- deterministic phrase mappings as a limited fallback, clearly labeled.

**Steps:**

1. Define a protocol returning typed `NaturalLanguageSearchIntent`, never query text.
2. Add fake, unavailable, delayed, malformed, and cancellation test providers.
3. Spike candidate runtime providers behind that protocol.
4. Evaluate availability on macOS, iPhone, iPad, and visionOS deployment targets.
5. Record privacy boundary, network requirement, expected latency, offline behavior, and fallback UX.
6. Select one production strategy before adding the user-facing field.
7. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests GrimoraKit/SEMANTIC_DISCOVERY.md
   git commit -m "docs: choose natural-language search provider"
   ```

**Decision gate:** If no provider meets privacy, availability, and quality requirements, ship semantic search without NLP rather than weakening the execution boundary.

### Task 22: Add preview-only “Describe cards” to Advanced Search

**Objective:** Deliver natural-language search as a small explicit workflow without restoring the removed global input-mode state machine.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraUI/NaturalLanguageSearchTranspiler.swift`
- Create: `GrimoraKit/Sources/GrimoraUI/NaturalLanguageSearchSection.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/AdvancedSearchSheet.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/AdvancedSearchGeneratedQueryBar.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/GrimoraEnvironment.swift`
- Test: `GrimoraKit/Tests/GrimoraUITests/NaturalLanguageSearchTranspilerTests.swift`
- Add: `GrimoraCrossPlatformUITests/NaturalLanguageSearchUITests.swift`

**Steps:**

1. Add a separate “Describe cards” field and **Translate** button to Advanced Search.
2. Translate once, validate, serialize, and populate a preview without executing.
3. Show assumptions such as “interpreted ‘under four mana’ as `mv<4`.”
4. Require the existing **Search** confirmation action.
5. Allow one constrained repair attempt after a validation failure; then show the rejected term and reason.
6. Never fall back to searching the original prose as bare card-name terms.
7. Cancel stale translation tasks when input changes or the sheet closes.
8. Keep prompt/history syncing out of this release.
9. Verify examples against fixture result IDs, not only expected query strings.
10. Commit:
    ```bash
    git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests GrimoraCrossPlatformUITests
    git commit -m "feat: translate card descriptions in Advanced Search"
    ```

### Task 23: Ground translation values in local catalog metadata

**Objective:** Let the translator resolve real card vocabulary without inventing proper nouns.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraCore/CardDatabase+SearchVocabulary.swift`
- Extend: `GrimoraKit/Sources/GrimoraUI/NaturalLanguageSearchTranspiler.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/SearchVocabularyTests.swift`
- Extend: translator tests.

**Steps:**

1. Add bounded read APIs for card names, types, keywords, set codes/names, artists, formats, and semantic tags.
2. Resolve explicit terms from the request against local vocabulary before model invocation where practical.
3. Return ambiguity rather than selecting silently.
4. Prevent the provider from introducing unresolved names, artists, or sets.
5. Cache vocabulary by catalog version and invalidate it after catalog installation.
6. Test typos, aliases, ambiguous set names, stale cache, and catalog swaps.
7. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests
   git commit -m "feat: ground natural-language search locally"
   ```

### Task 24: Add an explicit Ask action to main search

**Objective:** Make the proven translator convenient without changing normal syntax input semantics.

**Files:**
- Modify: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+SearchCommands.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+SearchExecution.swift`
- Modify: `GrimoraKit/Sources/GrimoraUI/MacSearchFloatingHeader.swift`
- Modify: the relevant phone/iPad/vision search toolbar surface identified during implementation.
- Extend: `GrimoraKit/Tests/GrimoraUITests/GrimoraAppModelTests.swift`
- Extend: `GrimoraCrossPlatformUITests/NaturalLanguageSearchUITests.swift`

**Steps:**

1. Add a one-shot **Ask** action beside the normal syntax field.
2. Present the same preview/assumption UI; do not auto-detect prose.
3. Add generation/cancellation IDs so stale results cannot replace current searches.
4. Record generated syntax in normal query history only after successful confirmed execution.
5. Keep raw prompts out of synced history for this release.
6. Verify unavailable provider, offline provider, cancellation, malformed response, validation rejection, and successful search.
7. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests/GrimoraUITests GrimoraCrossPlatformUITests
   git commit -m "feat: ask for cards from main search"
   ```

**Milestone E exit gate:** Natural language always becomes a visible, validated Grimora query before execution, works with semantic `otag:` clauses, and never bypasses the existing search boundary.

---

# Phase 7 — Move from affinity to deficit-aware deck recommendations

### Task 25: Add a versioned card-role and conversion ontology

**Objective:** Distinguish “similar to the deck” from “improves the deck.”

**Files:**
- Extend: `GrimoraKit/Sources/GrimoraCore/CardSemanticModels.swift`
- Create: `GrimoraKit/Sources/GrimoraCore/CardStrategicRole.swift`
- Create: `GrimoraKit/Tests/GrimoraCoreTests/CardStrategicRoleTests.swift`
- Update: `GrimoraKit/SEMANTIC_DISCOVERY.md`

**Initial role dimensions:**

- setup, enabler, engine, payoff, interaction, protection, recovery, threat, finisher;
- immediate versus delayed value;
- standalone versus dependency-heavy;
- conversions such as enchantment→cards, enchantment→creatures, graveyard→battlefield, tokens→damage.

**Steps:**

1. Define the minimal controlled role vocabulary and provenance rules.
2. Derive only high-confidence roles from existing functional tags and deterministic card facts.
3. Keep uncertain/model-proposed roles out of production recommendations.
4. Add a reviewed benchmark set containing decks that over-index on engines, payoffs, interaction, or expensive cards.
5. Version the role policy independently from raw Scryfall tag data.
6. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests GrimoraKit/SEMANTIC_DISCOVERY.md
   git commit -m "feat: define strategic card roles"
   ```

### Task 26: Add deck diagnostics and marginal-utility scoring

**Objective:** Rank candidates by what they add to the current list, not only by centroid similarity.

**Files:**
- Extend: `GrimoraKit/Sources/GrimoraCore/CardCollectionSemanticProfile.swift`
- Create: `GrimoraKit/Sources/GrimoraCore/CardCollectionRecommendationPlanner.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/CardCollectionRecommendationPlannerTests.swift`

**Steps:**

1. Calculate role saturation, early proactive plays, immediate board impact, setup-only density, threat/payoff density, resilience, and verified ending coverage.
2. Keep raw measurements separate from interpretation.
3. Score candidates using:
   ```text
   theme fit
   + deficit correction
   + deck synergy
   - existing redundancy
   - deployment/opportunity cost
   ```
4. Score possible cuts separately by redundancy and low marginal contribution.
5. Return additions and potential cuts as suggestions; never mutate automatically.
6. Add Sythis fixtures where another draw engine ranks below an on-theme low-cost threat/payoff when the deck already has excess draw.
7. Require every recommendation to include measured evidence.
8. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraCore GrimoraKit/Tests/GrimoraCoreTests
   git commit -m "feat: plan deficit-aware deck recommendations"
   ```

### Task 27: Surface diagnosis and suggested swaps in List Insights

**Objective:** Explain the deck's measured shape and let the user inspect—not blindly accept—possible changes.

**Files:**
- Extend: `GrimoraKit/Sources/GrimoraUI/CardCollectionInsightsView.swift`
- Extend: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+CollectionInsights.swift`
- Extend: list-insights Core/UI/cross-platform tests.

**Steps:**

1. Add a “Deck shape” section with measured strengths and shortages.
2. Add addition/cut pairings with before/after metric deltas.
3. Explain uncertainty and data coverage.
4. Require separate user actions to inspect, add, and remove cards.
5. Preserve user-selected/favourite cards where that signal exists; otherwise do not imply a card must be cut.
6. Verify no illegal/off-colour/duplicate recommendation escapes final filtering.
7. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests GrimoraCrossPlatformUITests
   git commit -m "feat: explain deck improvement suggestions"
   ```

**Milestone F exit gate:** The system can distinguish affinity from improvement and explain why a suggestion addresses a measured deck deficit.

---

# Phase 8 — Extend natural language from search to deck advice

### Task 28: Reuse the typed translator for deck-improvement intent

**Objective:** Convert requests such as “this deck is slow” into structured diagnostic hypotheses and desired profile changes.

**Files:**
- Create: `GrimoraKit/Sources/GrimoraCore/DeckAdviceIntent.swift`
- Create: `GrimoraKit/Sources/GrimoraUI/DeckAdviceTranspiler.swift`
- Test: `GrimoraKit/Tests/GrimoraCoreTests/DeckAdviceIntentTests.swift`
- Test: `GrimoraKit/Tests/GrimoraUITests/DeckAdviceTranspilerTests.swift`

**Steps:**

1. Define typed fields for symptoms, measurements to inspect, increases, decreases, preserved themes, and hard constraints.
2. Supply computed deck measurements to the interpreter; do not ask the model to calculate them.
3. Make “slow” consider distinct hypotheses: mana, curve, early action, setup latency, threat density, and inability to close.
4. Ask one clarification only when competing diagnoses remain after measurement.
5. Feed the validated intent into `CardCollectionRecommendationPlanner`.
6. Keep card selection deterministic and catalog-grounded.
7. Commit:
   ```bash
   git add GrimoraKit/Sources GrimoraKit/Tests
   git commit -m "feat: translate natural-language deck goals"
   ```

### Task 29: Add “Ask about this deck” to List Insights

**Objective:** Complete the original conversational vision without creating an autonomous deck editor.

**Files:**
- Extend: `GrimoraKit/Sources/GrimoraUI/CardCollectionInsightsView.swift`
- Extend: `GrimoraKit/Sources/GrimoraUI/GrimoraAppModel+CollectionInsights.swift`
- Extend: cross-platform tests.

**Steps:**

1. Add a text field and explicit **Analyze** action inside Insights.
2. Show the interpreted goal, measured diagnosis, and proposed additions/cuts before any mutation.
3. Link each explanation back to deck metrics and shared semantic concepts.
4. Preserve an unavailable/offline fallback that still shows deterministic list insights.
5. Never apply a batch of deck edits; reuse individual existing add/remove confirmations.
6. Verify the full four-platform matrix.
7. Commit:
   ```bash
   git add GrimoraKit/Sources/GrimoraUI GrimoraKit/Tests GrimoraCrossPlatformUITests
   git commit -m "feat: ask natural-language questions about a deck"
   ```

**Milestone G exit gate:** Natural-language deck advice is a constrained interface over measured diagnostics and deterministic recommendations, not a free-form model answer.

---

## 5. Combo support is a separate verified data product

Combos must not be inferred from pairwise tag similarity or accepted from a model. If combo-aware recommendations are approved later, add a separately versioned source and schema:

```text
semantic_combos
semantic_combo_pieces
semantic_combo_substitutions
semantic_combo_prerequisites
semantic_combo_outcomes
semantic_combo_sources
```

A combo release requires current Oracle verification, Commander legality/color checks, interaction-point text, source provenance, and dedicated tests. It is not a blocker for Releases A–F.

---

## 6. Testing and release verification matrix

### Per-task fast loop

```bash
swift test --package-path GrimoraKit --filter <FocusedTestType>
```

### Per-phase package gate

```bash
swift test --package-path GrimoraKit
```

### Engine/data phases

```bash
Tools/run_engine_tests.sh
Tools/run_engine_tests.sh --live
Tools/run_engine_tests.sh --full
```

The offline engine script must be expanded in Task 9 before it is accepted as the semantic-data gate.

### Runtime UI phases

Regenerate the project when project/source configuration changes:

```bash
xcodegen generate
```

Fast targeted loops:

```bash
Tools/test-fast.sh -p mac -o <test-identifier>
Tools/test-fast.sh -p ios -o <test-identifier>
Tools/test-fast.sh -p ipad -o <test-identifier>
Tools/test-fast.sh -p vision -o <test-identifier>
```

Pre-merge for every runtime slice:

```bash
Tools/test-fast.sh -p mac
Tools/test-fast.sh -p ios
Tools/test-fast.sh -p ipad
Tools/test-fast.sh -p vision
```

Also build/relaunch the locally testable macOS app and record the exact result. Report macOS, iOS, iPadOS, and visionOS separately, as required by `AGENTS.md`.

### Quality gates

- **Data integrity:** source counts reconcile, no orphan relationships, deterministic digests, and exact delta round trips.
- **Search correctness:** semantic syntax tests assert result card IDs.
- **Relationship quality:** the checked-in benchmark catches broad-tag dominance and metadata noise.
- **Recommendation safety:** no already-present, illegal, off-colour, or singleton-invalid candidate reaches an actionable result.
- **Explainability:** every relationship/recommendation exposes its strongest contributing concepts and provenance.
- **NLP hard constraints:** 100% of benchmark prompts stay within the typed field/operator policy, validate, compile, and introduce no ungrounded proper nouns. Semantic intent quality has a separately reviewed benchmark threshold before release.
- **Graph usability:** stable layout, bounded nodes/edges, accessibility list, and four-platform screenshot inspection.
- **Performance:** record cold/warm query, list-profile, graph-layout, memory, and artifact-size baselines; set release budgets from measured supported-device performance before activation.

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Scryfall tags include cycles, naming trivia, and inconsistent community coverage | Preserve provenance; disable non-gameplay branches; benchmark ranked outcomes; never treat Scryfall as perfect ground truth |
| Rare trivia receives excessive IDF weight | Apply `similarity_enabled` before weighting and test known metadata branches |
| Pairwise graph explosion | Derive bounded candidates through the inverted card-tag index; materialize top-K only if profiling proves necessary |
| Reprints duplicate nodes/recommendations | Use Oracle-level semantic keys everywhere and select one representative printing for UI/actions |
| Empty `main` tables shadow attached semantic catalog | Add all distributed semantic tables to `catalogTablesToDropFromMain` and test attached-catalog resolution |
| New semantic data is absent from delta verification | Add semantic digests and delta tables before first publish |
| Semantic source updates do not trigger builds | Add Oracle-tag source identity to `CatalogSourceVersions` and build-state comparison |
| Older manifests stop decoding | Make additive semantic manifest fields optional and test legacy fixtures |
| Scheduled builds publish partial semantics | Atomic download/expand/import; catalog validation; no publish before all gates pass |
| “Similar” is mistaken for “good addition” | Separate affinity Milestone C from deficit-aware Milestone F and label each recommendation mode |
| Graph becomes a hairball | List-bounded graph, top edges per node, global cap, stable layout, text summaries, and filtering |
| Low-connection label feels judgmental | Say “few semantic links,” expose reasons, and explain incomplete tag coverage |
| Natural-language search repeats the removed feature's complexity | Explicit action, preview-first, no global input mode, no synced raw prompt history in v1 |
| Model emits valid-looking but wrong syntax | Typed DTO, local vocabulary grounding, full validation, one repair, no fallback-to-prose |
| NLP provider is unavailable on one platform | Provider protocol, explicit availability UI, deterministic semantic search remains fully usable |
| Combo hallucinations | Separate curated combo product with verification and provenance; never model-generate production combo facts |
| Runtime feature regresses one Apple platform | Four-platform build/UI-test/relaunch evidence required for every UI slice |

---

## 8. Open decisions, with recommended defaults

1. **First semantic source:** Use Scryfall Oracle Tags only. Add custom/model concepts only after a reviewed quality benchmark.
2. **Hierarchy storage:** Decide from Task 2 measurements; do not preselect closure and flattened rows together.
3. **Natural-language provider:** Keep the protocol provider-neutral. Treat Ollama as development infrastructure, not a shipping dependency.
4. **Recommendation scope:** Start with all ordinary lists; add Commander-specific legality/color/singleton filtering when `ruleset == .commander`.
5. **Graph entry point:** Use an Insights sheet, not a third persisted list view mode.
6. **Graph layout:** Prefer deterministic layout and fitted first view over free-running physics.
7. **User history:** Store generated syntax only after confirmed search; defer raw prompt persistence/sync.
8. **Model enrichment:** If pursued, cache by Oracle rules hash + ontology + prompt + model version and keep model facts in separate provenance rows.
9. **Combos:** Defer until a trustworthy, licensed, versioned source and rules-verification process exist.
10. **Catalog rollout:** One intentional full download for the schema transition is acceptable; subsequent builds must have working semantic deltas.

---

## 9. Definition of final completion

The feature is complete only when all of the following are true:

- A current distributed catalog contains deterministic, validated, provenance-bearing Oracle-level semantic relationships.
- `function:`/`otag:` search works offline through the existing safe compiler.
- Card detail exposes functional tags and explainable related cards.
- Existing lists produce a local semantic profile, safe recommendations, and measured explanations.
- The list graph is accessible, bounded, interactive, and verified on macOS, iPhone, iPad, and visionOS.
- Natural-language card search produces a visible, validated Grimora syntax query before execution.
- Deficit-aware recommendations distinguish “more like this” from “improves this list.”
- Natural-language deck advice, if enabled, only selects diagnostic goals; computed data and deterministic ranking select cards.
- Full catalogs and semantic deltas pass logical-digest verification.
- Quality, performance, artifact growth, privacy, failure, and four-platform evidence are documented.
- No production recommendation or combo claim depends solely on unrestricted model output.
