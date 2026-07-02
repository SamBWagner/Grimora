#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import CoreImage
import ImageIO
import XCTest

/// Exercises `ScrySymbolMatcher` against the real catalog and real Scryfall
/// reference scans of every Captain of the Watch printing (`ScryCorpus/references/`).
///
/// The "scan" in these tests is a reference image put through a deterministic
/// perturbation (edge crop + rescale + blur) so the match is never a trivial
/// identical-bytes comparison — it has to survive the kind of geometry and focus
/// error a rectified camera crop carries. Real captures should still join the
/// corpus as they become available; this validates the mechanism, not device
/// conditions.
final class ScrySymbolMatcherTests: XCTestCase {
  // MARK: - The M13 #8 / GN3 #8 collision

  func testSymbolMatchSettlesNumberCollision() throws {
    // Name + collector number 8 matches two printings (M13 and Game Night 2022);
    // the old frame prints no set code, so text alone is stuck. The set symbol
    // is the discriminating signal.
    let resolver = ScryCardResolver(database: try Self.database())
    let resolution = try resolver.resolve(
      ScrySignals(name: "Captain of the Watch", collectorNumber: "8")
    )
    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertEqual(Set(resolution.candidates.map(\.setCode)), ["m13", "gn3"])

    let scan = try Self.perturbed(Self.referenceImage("gn3-8"))
    let refined = ScrySymbolMatcher().refine(
      resolution,
      scan: scan,
      referenceImages: try Self.references(for: resolution.candidates)
    )

    XCTAssertEqual(refined.confidence, .auto)
    XCTAssertEqual(refined.method, .nameAndVisual)
    XCTAssertEqual(refined.card?.setCode, "gn3")
  }

  func testContradictingCopyrightYearVetoesAutoPromotion() throws {
    // The symbol says GN3 (2022) but the copyright line read 2012 — two
    // disagreeing signals must surface the picker, not guess.
    let resolver = ScryCardResolver(database: try Self.database())
    let resolution = try resolver.resolve(
      ScrySignals(name: "Captain of the Watch", collectorNumber: "8", copyrightYear: 2012)
    )
    XCTAssertEqual(resolution.confidence, .ambiguous)

    let scan = try Self.perturbed(Self.referenceImage("gn3-8"))
    let refined = ScrySymbolMatcher().refine(
      resolution,
      scan: scan,
      referenceImages: try Self.references(for: resolution.candidates)
    )

    XCTAssertEqual(refined.confidence, .ambiguous, "conflicting year+symbol must not auto-accept")
    XCTAssertNil(refined.card)
    // The visual evidence still improves the picker order.
    XCTAssertEqual(refined.candidates.first?.setCode, "gn3")
  }

  // MARK: - The full 8-printing picker (name only, nothing else read)

  func testSymbolMatchRanksOldFramePrintingPicker() throws {
    let resolver = ScryCardResolver(database: try Self.database())
    let resolution = try resolver.resolve(ScrySignals(name: "Captain of the Watch"))
    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertEqual(resolution.candidates.count, 8)

    let scan = try Self.perturbed(Self.corpusImage("captain-of-the-watch-m10-6.jpg"))
    let refined = ScrySymbolMatcher().refine(
      resolution,
      scan: scan,
      referenceImages: try Self.references(for: resolution.candidates)
    )

    // M10 and M13 differ only by a tiny numeral in the symbol, so the matcher
    // may rank them adjacently without a decisive gap — but the scanned printing
    // must come first, and a wrong card must never auto-accept.
    XCTAssertEqual(refined.candidates.first?.setCode, "m10")
    if refined.confidence == .auto {
      XCTAssertEqual(refined.card?.setCode, "m10")
    }
  }

  // MARK: - Precision guards

  func testPartialReferencesLeaveResolutionUntouched() throws {
    let resolver = ScryCardResolver(database: try Self.database())
    let resolution = try resolver.resolve(ScrySignals(name: "Captain of the Watch"))

    let scan = try Self.perturbed(Self.corpusImage("captain-of-the-watch-m10-6.jpg"))
    var references = try Self.references(for: resolution.candidates)
    references.removeValue(forKey: resolution.candidates[0].id)

    let refined = ScrySymbolMatcher().refine(resolution, scan: scan, referenceImages: references)

    XCTAssertEqual(refined.confidence, .ambiguous)
    XCTAssertEqual(refined.candidates.map(\.id), resolution.candidates.map(\.id))
  }

  func testMixedNameCandidatesAreNotRefined() throws {
    // Refinement is a printing-picker aid; a name-conflict ambiguity (different
    // cards) is out of scope and must pass through unchanged.
    let database = try Self.database()
    let captain = try XCTUnwrap(database.card(setCode: "m10", collectorNumber: "6"))
    let other = try XCTUnwrap(database.card(setCode: "m10", collectorNumber: "7"))
    let resolution = ScryResolution(
      card: nil,
      candidates: [captain, other],
      confidence: .ambiguous,
      method: .exactKey,
      signals: ScrySignals(name: "Captain of the Watch")
    )

    let scan = try Self.perturbed(Self.corpusImage("captain-of-the-watch-m10-6.jpg"))
    let refined = ScrySymbolMatcher().refine(
      resolution,
      scan: scan,
      referenceImages: try Self.references(for: [captain])
    )

    XCTAssertEqual(refined.confidence, .ambiguous)
    XCTAssertEqual(refined.candidates.map(\.id), resolution.candidates.map(\.id))
  }

  func testUnsupportedLayoutCandidateBlocksRefinement() throws {
    // A split/battle/flip candidate can't be measured by a fixed reference
    // band; by the full-coverage rule its presence must leave the picker
    // untouched rather than promote around it.
    let resolver = ScryCardResolver(database: try Self.database())
    let base = try resolver.resolve(ScrySignals(name: "Captain of the Watch", collectorNumber: "8"))
    var candidates = base.candidates
    candidates[0].layout = "split"
    let resolution = ScryResolution(
      card: nil,
      candidates: candidates,
      confidence: .ambiguous,
      method: .nameAndNumber,
      signals: base.signals
    )

    let scan = try Self.perturbed(Self.referenceImage("gn3-8"))
    let refined = ScrySymbolMatcher().refine(
      resolution,
      scan: scan,
      referenceImages: try Self.references(for: base.candidates)
    )

    XCTAssertEqual(refined.confidence, .ambiguous)
    XCTAssertEqual(refined.candidates.map(\.id), candidates.map(\.id))
  }

  // MARK: - Feature-print cache

  func testFeaturePrintCacheHitsAndEvictsLRU() throws {
    let cache = ScryFeaturePrintCache(capacity: 2)
    let band = ScrySymbolBand.standard
    let image = try Self.referenceImage("m10-6")
    let crop = try XCTUnwrap(ScrySymbolMatcher.crop(image, band: band))
    let observation = try ScrySymbolMatcher.featurePrint(of: crop)

    cache.store(observation, cardID: "a", band: band)
    XCTAssertTrue(cache.hasObservation(for: "a", band: band))
    XCTAssertFalse(cache.hasObservation(for: "a", band: ScrySymbolBand.low), "band is part of the key")

    cache.store(observation, cardID: "b", band: band)
    _ = cache.observation(for: "a", band: band)  // refresh a → b is now least recent
    cache.store(observation, cardID: "c", band: band)

    XCTAssertTrue(cache.hasObservation(for: "a", band: band))
    XCTAssertFalse(cache.hasObservation(for: "b", band: band), "least-recently-used entry evicted")
    XCTAssertTrue(cache.hasObservation(for: "c", band: band))
  }

  // MARK: - Fixtures

  static func database() throws -> CardDatabase {
    try ScryTestCatalog.requireShared()
  }

  static func corpusURL() throws -> URL {
    try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("ScryCorpus", isDirectory: true)
  }

  static func corpusImage(_ name: String) throws -> CGImage {
    try loadImage(corpusURL().appendingPathComponent("images").appendingPathComponent(name))
  }

  /// A reference scan by `<setCode>-<collectorNumber>` under `references/`.
  static func referenceImage(_ key: String) throws -> CGImage {
    try loadImage(corpusURL().appendingPathComponent("references").appendingPathComponent("\(key).jpg"))
  }

  /// Reference images keyed by candidate card id, as the matcher expects.
  static func references(for candidates: [CardRecord]) throws -> [String: CGImage] {
    var images: [String: CGImage] = [:]
    for candidate in candidates {
      images[candidate.id] = try referenceImage("\(candidate.setCode)-\(candidate.collectorNumber)")
    }
    return images
  }

  static func loadImage(_ url: URL) throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), url.lastPathComponent)
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), url.lastPathComponent)
  }

  /// Deterministic stand-in for rectification error: shave 1.5% off the left and
  /// 1% off the top (imperfect quad), rescale to 900px wide, soften focus.
  static func perturbed(_ image: CGImage) throws -> CGImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let cropped = try XCTUnwrap(image.cropping(
      to: CGRect(x: width * 0.015, y: height * 0.010, width: width * 0.985, height: height * 0.990)
    ))

    var output = CIImage(cgImage: cropped)
    let scale = 900.0 / output.extent.width
    if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
      lanczos.setValue(output, forKey: kCIInputImageKey)
      lanczos.setValue(scale, forKey: kCIInputScaleKey)
      lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
      output = try XCTUnwrap(lanczos.outputImage)
    }
    let extent = output.extent
    if let blur = CIFilter(name: "CIGaussianBlur") {
      blur.setValue(output, forKey: kCIInputImageKey)
      blur.setValue(1.2, forKey: kCIInputRadiusKey)
      output = try XCTUnwrap(blur.outputImage)
    }
    return try XCTUnwrap(CIContext().createCGImage(output, from: extent))
  }
}
#endif
