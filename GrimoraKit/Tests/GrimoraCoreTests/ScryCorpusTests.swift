#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import ImageIO
import XCTest

/// Runs the pipeline (`ScryTextExtractor` → `ScryCardResolver`) over the labeled
/// single-card crops against the **real** Scryfall catalog (`ScryTestCatalog`),
/// and enforces the product contract:
///
/// - **Precision (hard gate, every entry):** never auto-accept the *wrong* card.
///   Identity is checked by real (set code, collector number) against the real
///   catalog, so a correct result has to beat genuine reprints and set-mates —
///   not a handful of planted answers.
/// - **Recall (per-entry `expectation`):** `auto` entries (the default) must
///   auto-accept the correct card. `disambiguation` entries only have to surface
///   the correct printing among the candidates — the honest outcome for cards
///   whose printed signals can't uniquely identify them (a 1994 card with no
///   collector number, say). Upgrading an entry to `auto` is the recall ratchet;
///   the test reports `disambiguation` entries that already auto-accept.
///
/// Crucially, the resolver is handed only the image-derived signals and the full
/// catalog; the expected answer is used *only* in the assertion.
final class ScryCorpusTests: XCTestCase {
  struct Manifest: Decodable { var entries: [Entry] }

  enum Expectation: String, Decodable {
    /// Must auto-accept the correct printing (default).
    case auto
    /// Must surface the correct printing among the disambiguation candidates;
    /// auto-accepting the correct printing is also fine (and worth upgrading).
    case disambiguation
    /// A permanent *historical* tag: this card was hard when captured (a wrong
    /// auto-accept, a missing candidate, or unresolved), stored with the correct
    /// ground truth. It is **not** exempt — every real card must scan, so a
    /// knownFailure entry still has to be identified (auto-accept the correct
    /// printing, or surface it among the candidates) or it fails like any other
    /// entry. The tag records history: it is never removed and never "upgraded".
    case knownFailure
  }

  struct Entry: Decodable {
    var image: String
    var name: String
    var setCode: String
    var collectorNumber: String
    var expectation: Expectation?
    var foil: Bool?
    var sleeved: Bool?
    var background: String?
    var notes: String?

    var resolvedExpectation: Expectation { expectation ?? .auto }
  }

  func testCorpusResolvesEveryCropAgainstRealCatalog() throws {
    let manifest = try Self.loadManifest()
    try XCTSkipIf(
      manifest.entries.isEmpty,
      "Scry corpus is empty — add labeled crops to ScryCorpus/images and manifest.json."
    )
    // The images themselves are a gitignored local-only asset store; a checkout
    // without them skips rather than fails. A *partially* present store still
    // fails per-entry below — that's accidental deletion, not a fresh clone.
    try XCTSkipIf(
      Self.corpusURL().map { !FileManager.default.fileExists(atPath: $0.appendingPathComponent("images").path) } ?? true,
      "ScryCorpus/images not on this checkout — local-only assets (see ScryCorpus/README.md)"
    )

    let database = try ScryTestCatalog.requireShared()
    let scanner = ScryScanner(database: database)

    var autoCorrect = 0
    var failures: [String] = []
    var report = "\nScry crop resolution (real catalog, \(try database.cardCount()) cards):\n"

    for entry in manifest.entries {
      guard let (image, orientation) = Self.loadImage(entry.image) else {
        XCTFail("Could not load corpus image \(entry.image)")
        continue
      }

      // The production path for an already-rectified crop: the 4-rotation
      // identify loop (which split/battle layouts need), not a single upright
      // extraction.
      let upright = ScryTextExtractor.makeUpright(image, orientation: orientation)
      let result = try scanner.identify(rectified: upright, detectedCard: Self.placeholderCard)
      let resolution = result.resolution
      let signals = resolution.signals
      let read = "set=\(signals.setCode ?? "—") num=\(signals.collectorNumber ?? "—")"
      let expectation = entry.resolvedExpectation

      if expectation == .knownFailure {
        // `knownFailure` is a permanent *historical* tag ("this card was hard
        // when captured") — it no longer EXEMPTS the card. Every real card must
        // scan: it has to be identified (auto-accept the correct printing, or
        // surface it among disambiguation candidates). Resolving to none, the
        // wrong card, or a candidate list missing the correct printing is a real
        // failure, exactly like any other entry. The tag is never removed and is
        // never "upgraded" — it just records history.
        let identifiedAuto = resolution.confidence == .auto && Self.matches(resolution.card, entry)
        let identifiedAmbiguous = resolution.confidence == .ambiguous
          && resolution.candidates.contains { Self.matches($0, entry) }
        if identifiedAuto {
          autoCorrect += 1
          report += "  ✓ \(entry.image)  [historically hard — now auto]  \(read)\n"
        } else if identifiedAmbiguous {
          report += "  ✓ \(entry.image)  [historically hard — identified via disambiguation]  \(read)\n"
        } else {
          failures.append("\(entry.image): historically-hard card still not scannable (\(Self.describe(resolution.card)) / \(resolution.confidence))  \(read)")
          report += "  ✗ \(entry.image)  not scannable yet (\(Self.describe(resolution.card)) / \(resolution.confidence))  \(read)\n"
        }
        continue
      }

      switch resolution.confidence {
      case .auto:
        if Self.matches(resolution.card, entry) {
          autoCorrect += 1
          let ratchet = expectation == .disambiguation ? "  (exceeds expectation — consider upgrading to auto)" : ""
          report += "  ✓ \(entry.image)  [\(resolution.method.rawValue)]  \(read)\(ratchet)\n"
        } else {
          // Precision is the hard gate for every expectation level.
          failures.append("\(entry.image): auto-accepted \(Self.describe(resolution.card)), expected \(entry.setCode) \(entry.collectorNumber)")
          report += "  ✗ WRONG \(entry.image)  got \(Self.describe(resolution.card))\n"
        }
      case .ambiguous:
        let present = resolution.candidates.contains { Self.matches($0, entry) }
        report += "  ? \(entry.image)  disambiguate (correct present: \(present))  \(read)\n"
        switch expectation {
        case .auto:
          failures.append("\(entry.image): expected a clean auto-accept but got disambiguation  (\(read))")
        case .disambiguation:
          if !present {
            failures.append("\(entry.image): correct printing missing from disambiguation candidates  (\(read))")
          }
        case .knownFailure:
          break  // handled (and `continue`d) above
        }
      case .none:
        report += "  – \(entry.image)  unresolved  \(read)\n"
        failures.append("\(entry.image): resolved to none  (\(read))")
      }
    }

    report += "auto-accepted correctly \(autoCorrect)/\(manifest.entries.count)\n"
    print(report)
    // The test runner truncates large print buffers; SCRY_REPORT_DIR gets the
    // full report on disk (the corpus is big enough now that this matters).
    if let dir = ProcessInfo.processInfo.environment["SCRY_REPORT_DIR"] {
      try? report.write(
        to: URL(fileURLWithPath: dir).appendingPathComponent("crops.txt"),
        atomically: true, encoding: .utf8
      )
    }
    XCTAssertTrue(failures.isEmpty, "Crop failures:\n" + failures.joined(separator: "\n"))
  }

  /// The **bulk decision path**. Bulk mode commits straight off
  /// `ScryScanner.previewScan` (a fast, single-orientation, no-retry read) with no
  /// follow-up full scan, so a confident preview of the *wrong* printing is a real
  /// wrong-auto-accept the full-scan test above never exercises. Precision is the
  /// hard gate here; recall is intentionally lenient — preview is a subset, so a
  /// crop that simply doesn't confidently commit is reported, never failed.
  func testPreviewScanNeverWronglyAutoCommitsCropAgainstRealCatalog() throws {
    let manifest = try Self.loadManifest()
    try XCTSkipIf(
      manifest.entries.isEmpty,
      "Scry corpus is empty — add labeled crops to ScryCorpus/images and manifest.json."
    )
    try XCTSkipIf(
      Self.corpusURL().map { !FileManager.default.fileExists(atPath: $0.appendingPathComponent("images").path) } ?? true,
      "ScryCorpus/images not on this checkout — local-only assets (see ScryCorpus/README.md)"
    )

    let database = try ScryTestCatalog.requireShared()
    let scanner = ScryScanner(database: database)

    var committedCorrect = 0
    var committed = 0
    var failures: [String] = []
    var report = "\nScry preview-path (bulk commit) precision (real catalog, \(try database.cardCount()) cards):\n"

    for entry in manifest.entries {
      guard let (image, orientation) = Self.loadImage(entry.image) else {
        XCTFail("Could not load corpus image \(entry.image)")
        continue
      }

      // Bulk seeds previewScan with the current live detection; corpus crops are
      // already rectified, so the full-frame placeholder quad stands in.
      let upright = ScryTextExtractor.makeUpright(image, orientation: orientation)
      let resolution = try scanner.previewScan(
        upright, orientation: .up, seedCard: Self.placeholderCard, readingOrientation: .up
      )
      // Bulk commits only on a confident preview (`.auto`, which carries a card).
      let committedCard = resolution?.confidence == .auto ? resolution?.card : nil
      let read = "set=\(resolution?.signals.setCode ?? "—") num=\(resolution?.signals.collectorNumber ?? "—")"

      if entry.resolvedExpectation == .knownFailure {
        if let committedCard, Self.matches(committedCard, entry) {
          report += "  ! \(entry.image)  knownFailure NOW commits correctly on preview — revisit\n"
        } else {
          report += "  · \(entry.image)  knownFailure (preview: \(Self.describe(committedCard)))  \(read)\n"
        }
        continue
      }

      guard let committedCard else {
        report += "  – \(entry.image)  no confident preview commit  \(read)\n"
        continue
      }
      committed += 1
      if Self.matches(committedCard, entry) {
        committedCorrect += 1
        report += "  ✓ \(entry.image)  preview commit correct  \(read)\n"
      } else {
        failures.append("\(entry.image): preview auto-committed \(Self.describe(committedCard)), expected \(entry.setCode) \(entry.collectorNumber)")
        report += "  ✗ WRONG \(entry.image)  preview committed \(Self.describe(committedCard))\n"
      }
    }

    report += "confident preview commits correct \(committedCorrect)/\(committed)\n"
    print(report)
    if let dir = ProcessInfo.processInfo.environment["SCRY_REPORT_DIR"] {
      try? report.write(
        to: URL(fileURLWithPath: dir).appendingPathComponent("crops-preview.txt"),
        atomically: true, encoding: .utf8
      )
    }
    XCTAssertTrue(
      failures.isEmpty,
      "Preview-path (bulk) precision failures — bulk mode would auto-commit the wrong printing:\n"
        + failures.joined(separator: "\n")
    )
  }

  /// `identify` only reads the detection for bookkeeping; corpus crops are
  /// already rectified, so a synthetic full-frame quad stands in.
  static let placeholderCard = ScryDetectedCard(
    normalizedCorners: [
      CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
    ],
    areaFraction: 1,
    aspectRatio: 0.714,
    confidence: 1
  )

  // MARK: - Identity (real set code + collector number)

  static func matches(_ card: CardRecord?, _ entry: Entry) -> Bool {
    guard let card else { return false }
    return card.setCode.lowercased() == entry.setCode.lowercased()
      && card.collectorNumber == entry.collectorNumber
  }

  static func describe(_ card: CardRecord?) -> String {
    guard let card else { return "nil" }
    return "\(card.name) [\(card.setCode) \(card.collectorNumber)]"
  }

  // MARK: - Loading

  private static func corpusURL() -> URL? {
    Bundle.module.resourceURL?.appendingPathComponent("ScryCorpus", isDirectory: true)
  }

  static func loadManifest() throws -> Manifest {
    guard let url = corpusURL()?.appendingPathComponent("manifest.json"),
          FileManager.default.fileExists(atPath: url.path) else {
      return Manifest(entries: [])
    }
    return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
  }

  static func loadImage(_ name: String) -> (CGImage, CGImagePropertyOrientation)? {
    guard let url = corpusURL()?.appendingPathComponent("images").appendingPathComponent(name),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }
    var orientation = CGImagePropertyOrientation.up
    if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let raw = props[kCGImagePropertyOrientation] as? UInt32,
       let parsed = CGImagePropertyOrientation(rawValue: raw) {
      orientation = parsed
    }
    return (image, orientation)
  }
}
#endif
