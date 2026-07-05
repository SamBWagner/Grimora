# Grimora Scry — recognition test harness

Dev-only iOS app (bundle `com.samwagner.GrimoraScry`, **never shipped**) for
growing the Scry recognition test corpus from real cards, on real hardware, with
no manual file shuffling.

## Same engine as the app
The harness scans through the **exact** recognition code the shipping app uses —
`GrimoraCore/Scry` (`ScryScanner` → `ScryCardDetector` / `ScryTextExtractor` /
`ScryCardResolver`), driven via `ScryCameraController` from `GrimoraUI`. Nothing
about recognition is reimplemented here; the harness UI only *captures and marks*
scans. So a card that passes/fails here passes/fails on the code that ships. The
corpus those captures build (`ScryCorpusTests` / `ScrySceneTests`) is the
regression suite.

## The loop
1. Point at a card. The live preview shows what the engine thinks.
2. **Still ⇄ Live** toggle chooses the input to capture — *Still* = deliberate
   high-res still (≈ a regular scan), *Live* = video frame (≈ the bulk/passive
   commit input). Both run the identical `ScryScanner`.
3. Tap to scan → a review sheet with the engine's answer.
4. Mark **Correct** or **Wrong** (search / pick the true card when wrong; tap a
   candidate when the engine was ambiguous). One explicit verdict per card.
5. Each verdict saves a still + rectified crop + JSON sidecar.

The verdict maps to a corpus `expectation`: correct→`auto`,
correct-via-candidate-pick→`disambiguation`, wrong→`knownFailure`.

## Zero-touch transfer (iCloud)
Captures write into the app's **iCloud Drive** container
(`iCloud.com.samwagner.GrimoraScry`, entitlement = iCloud **Documents** only, not
CloudKit — the harness runs no sync transport). They appear on the Mac at:

```
~/Library/Mobile Documents/iCloud~com~samwagner~GrimoraScry/Documents/Captures
```

with no dragging. If iCloud is unavailable the app falls back to local
`Documents/Captures` (still Finder-visible via file sharing) and shows a
**Local only** badge instead of **iCloud**.

## Generating tests (no interaction)
Ask an agent to "generate tests from the new scans"; it runs:

```
Tools/scry_sync_captures.sh --tests
```

which materializes the synced captures, imports them into the corpus (appends the
manifests, maps verdicts → expectations), rebuilds the catalog if new cards
appeared, prints the new cards, and runs the corpus + scene suites. Processed
captures move to `imported/` (syncing back to clear the phone's list).

## Build / run
`open Grimora.xcodeproj`, **GrimoraScry** scheme, run on a physical iPhone (the
camera needs real hardware). Project is generated — edit `project.yml` then
`xcodegen generate`, never the `.xcodeproj`. First device build may need the
iCloud container enabled for the App ID in automatic signing.
