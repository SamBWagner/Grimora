# Scry recognition corpus

Labeled real-card photos that `ScryCorpusTests` runs the recognition pipeline
against to guard accuracy (precision/recall) and latency.

## Local-only asset store (important)

The pixels — `images/`, `scenes/`, and `catalog.json.gz` — are **gitignored**:
at 200MB+ and growing with every capture round they don't belong in the repo.
Only the ground truth (`manifest.json`, `scenes-manifest.json`, this README) and
the small stable `references/` set are tracked. Consequences:

- On a checkout without the assets, the corpus/scene suites **skip** (with a
  message pointing here) instead of failing. On the dev machine with assets
  present, every manifest entry is enforced as usual.
- `catalog.json.gz` is rebuilt from the manifests by
  `Tools/scry_build_corpus_catalog.py` (rate-limited Scryfall fetch).
- The image master lives in this working tree only; raw capture backups sit in
  `~/Downloads/Captures*/imported/`. Back the corpus up externally before
  cleaning either location.

## Layout
- `manifest.json` — ground-truth labels for the single-card crops in `images/`.
- `images/` — single-card crops, roughly upright, ~1600px on the long edge
  (a stand-in for the rectified crop the live camera produces after rectangle
  detection). EXIF orientation is baked in (upright). The Captain of the Watch
  entry is a Scryfall scan standing in for a real photo — it covers the old
  (2003) frame, whose collector info is a tiny `6/249` at the end of the
  copyright line and which prints no set code at all.
- `scenes-manifest.json` + `scenes/` — full raw desk photos (multiple cards,
  clutter, rotation, upside-down) for the end-to-end detection pipeline.
- `references/` — Scryfall scans of candidate printings, named
  `<setCode>-<collectorNumber>.jpg` (currently every Captain of the Watch
  printing). `ScrySymbolMatcherTests` uses them as the reference side of
  set-symbol matching, with a perturbed copy standing in for the scan.
- `catalog.json.gz` — a **real Scryfall snapshot** (~1,450 cards: every printing
  of each corpus card's name plus the full involved sets, M10 included).
  `ScryTestCatalog` builds the test database from this.

## Black-box principle (important)
The tests resolve against the **real catalog**, never a database built from the
expected answers — otherwise we'd be hardcoding success. Each target card is
present only because it's a real Magic card surrounded by its real reprints and
set-mates (Izzet Boilerworks has 24 printings here). The pipeline sees only the
image + catalog; the expected answer is used **only in the assertion**, and
identity is checked by real (set code, collector number). Ground truth comes from
Scryfall, not eyeballing — that's how the "Hollow Marauder #60" mistake (really
#90) got caught.

## Manifest entry fields
| field | meaning |
|---|---|
| `image` | filename under `images/` |
| `name` | exact card name |
| `setCode` | Scryfall set code, lowercase (e.g. `otj`) |
| `collectorNumber` | collector number, leading zeros stripped (`0005` → `5`) |
| `expectation` | `auto` (default: must auto-accept correctly), `disambiguation` (must surface the correct printing among candidates; never a wrong auto-accept), or `knownFailure` (a documented live engine failure — wrong auto-accept, missing candidate, or unresolved — stored with correct ground truth; exempt from the gates, reported only, and flagged loudly once it starts passing so it can be upgraded). Upgrading an entry is the recall ratchet — the test report flags `disambiguation` entries that already auto-accept and `knownFailure` entries that now pass. |
| `foil` | true if a foil printing (star in the collector line) |
| `sleeved` | true if photographed through a plastic sleeve |
| `background` | rough capture background (`black`, `wood`, …) |
| `notes` | free text |

## Adding photos
1. Drop a single-card crop into `images/`.
2. Add a matching entry to `manifest.json` (set `expectation` honestly — a card
   whose printed signals can't uniquely identify it belongs at `disambiguation`,
   and a capture the engine currently gets wrong belongs at `knownFailure`).
3. Rebuild the catalog so the new card's real printings and set-mates are
   present: `Tools/scry_build_corpus_catalog.py` (or `--check` to verify without
   fetching). The script fetches every printing of each corpus name plus each
   entry's full set (capped at 450 cards/set), unions with the existing catalog,
   and never drops cards.
4. Run `swift test --package-path GrimoraKit --filter ScryCorpusTests`.

### The fast path: the Grimora Scry harness app
The `GrimoraScry` iOS target (dev-only, never shipped) runs the real engine
on-device: scan a card, mark the answer **Correct**/**Wrong** (picking the true
card when wrong), and every verdict lands in the app's `Documents/Captures/` as
a still + rectified crop + JSON sidecar. Drag that folder off the phone in
Finder, then run `Tools/scry_import_captures.py <folder>` — it copies crops into
`images/`, stills into `scenes/`, appends both manifests with the right
`expectation` (correct→`auto`, picked-from-candidates→`disambiguation`,
wrong→`knownFailure`), and finishes with a catalog `--check`.

## Latency
`ScryLatencyBenchmarkTests` prints a report-only timing table (extractor
accurate/fast per crop, full scan per scene, symbol-matcher distances) when run
with `SCRY_BENCHMARK=1` — the before/after instrument for speed work.

`ScryCorpusTests` runs the **whole pipeline** (extractor → resolver against a
small real-card DB), because that's what matters: OCR may mangle a set code, but
the resolver recovers via the reliably-read name + collector number.

- **Precision (hard gate):** never auto-accept the *wrong* card.
- **Recall (reported, ratcheted):** how many auto-accept correctly vs. fall to
  disambiguation (where the right card must still be among the candidates).
