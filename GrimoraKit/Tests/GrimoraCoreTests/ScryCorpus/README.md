# Scry recognition corpus

Labeled real-card photos that `ScryCorpusTests` runs the recognition pipeline
against to guard accuracy (precision/recall) and latency.

## Layout
- `manifest.json` — ground-truth labels for the single-card crops in `images/`.
- `images/` — single-card crops, roughly upright, ~1600px on the long edge
  (a stand-in for the rectified crop the live camera produces after rectangle
  detection). EXIF orientation is baked in (upright).
- `scenes-manifest.json` + `scenes/` — full raw desk photos (multiple cards,
  clutter, rotation, upside-down) for the end-to-end detection pipeline.
- `catalog.json.gz` — a **real Scryfall snapshot** (~1,200 cards: every printing
  of each corpus card's name plus the full involved sets). `ScryTestCatalog`
  builds the test database from this.

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
| `foil` | true if a foil printing (star in the collector line) |
| `sleeved` | true if photographed through a plastic sleeve |
| `background` | rough capture background (`black`, `wood`, …) |
| `notes` | free text |

## Adding photos
1. Drop a single-card crop into `images/`.
2. Add a matching entry to `manifest.json`.
3. Run `swift test --package-path GrimoraKit --filter ScryCorpusTests`.

`ScryCorpusTests` runs the **whole pipeline** (extractor → resolver against a
small real-card DB), because that's what matters: OCR may mangle a set code, but
the resolver recovers via the reliably-read name + collector number.

- **Precision (hard gate):** never auto-accept the *wrong* card.
- **Recall (reported, ratcheted):** how many auto-accept correctly vs. fall to
  disambiguation (where the right card must still be among the candidates).
