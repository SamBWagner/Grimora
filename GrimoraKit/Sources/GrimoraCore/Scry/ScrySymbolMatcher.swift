#if canImport(Vision)
import CoreGraphics
import Foundation
import Vision

/// Disambiguates same-name printings by comparing the **set symbol** region of
/// the scanned card against reference images of each candidate printing.
///
/// Every Magic frame since Alpha's successors puts the expansion symbol at the
/// right end of the type-line band (roughly 54–64% down the card), and that
/// symbol is unique per set — it is exactly the signal a human uses to tell an
/// M10 reprint from an M13 one. The matcher crops the *same* normalized band
/// from the scan and from each candidate's reference image and compares Vision
/// feature prints; the true printing's band matches (same symbol on the same
/// frame furniture), while other printings differ in symbol, frame era, or both.
///
/// Precision rules, in keeping with the resolver's cardinal rule:
/// - refinement only runs when **all** candidates are printings of one name —
///   this is a printing picker aid, not a card identifier;
/// - auto-accept needs reference images for **every** candidate (an unmeasured
///   candidate can't be ruled out), a best distance under `maxAcceptDistance`,
///   and a runner-up at least `minRunnerUpRatio` times farther — a *relative*
///   margin, because absolute distances swell with resolution and focus
///   differences while the correct/incorrect ratio stays put;
/// - an OCR'd copyright year that contradicts the visual winner vetoes the
///   auto-accept (two disagreeing signals mean the scan is not trustworthy);
/// - with partial references the candidate order is left untouched.
public struct ScrySymbolMatcher: Sendable {
  /// The fallback scan-side band (origin top-left, normalized) used when no
  /// `ScryLineMap` anchored the symbol from the card's own type line. Reference
  /// bands always come from candidate metadata via `ScrySymbolBand`.
  public var band: CGRect

  /// Feature-print distance at or below which the best candidate may auto-accept.
  public var maxAcceptDistance: Float

  /// The runner-up must be at least this many times farther than the best match
  /// for the match to count as decisive.
  public var minRunnerUpRatio: Float

  /// Defaults tuned on a perturbed-query distance matrix over Captain of the
  /// Watch (M10/M13/DDO/GN3) at mixed resolutions: correct printings scored
  /// 0.41–0.69 with runner-up ratios ≥ 1.3; wrong printings never scored under
  /// 0.69, and all-wrong candidate sets cluster near ratio 1. The intentional
  /// near-tie is M10 vs M13 (same art, symbol differs only by a tiny numeral,
  /// ratio ≈ 1.14) — that pair stays ambiguous and is settled by collector
  /// number or year.
  public init(
    band: CGRect = CGRect(x: 0.70, y: 0.535, width: 0.26, height: 0.10),
    maxAcceptDistance: Float = 0.72,
    minRunnerUpRatio: Float = 1.25
  ) {
    self.band = band
    self.maxAcceptDistance = maxAcceptDistance
    self.minRunnerUpRatio = minRunnerUpRatio
  }

  /// Distance of each candidate's symbol band from the scan's, ascending
  /// (best first). Candidates without a reference image — or whose layout
  /// defeats reference-band cropping — are omitted.
  public func distances(
    scan: CGImage,
    scanBand: CGRect? = nil,
    candidates: [CardRecord],
    referenceImages: [String: CGImage],
    referenceCache: ScryFeaturePrintCache? = nil
  ) -> [(cardID: String, distance: Float)] {
    guard let scanCrop = Self.crop(scan, band: scanBand ?? band),
          let scanPrint = try? Self.featurePrint(of: scanCrop) else { return [] }

    var measured: [(cardID: String, distance: Float)] = []
    for candidate in candidates {
      guard let referenceBand = ScrySymbolBand.referenceBand(for: candidate) else { continue }

      let referencePrint: VNFeaturePrintObservation
      if let cached = referenceCache?.observation(for: candidate.id, band: referenceBand) {
        referencePrint = cached
      } else {
        guard let reference = referenceImages[candidate.id],
              let referenceCrop = Self.crop(reference, band: referenceBand),
              let computed = try? Self.featurePrint(of: referenceCrop) else { continue }
        referenceCache?.store(computed, cardID: candidate.id, band: referenceBand)
        referencePrint = computed
      }

      var distance: Float = 0
      guard (try? scanPrint.computeDistance(&distance, to: referencePrint)) != nil else { continue }
      measured.append((candidate.id, distance))
    }
    return measured.sorted { $0.distance < $1.distance }
  }

  /// Refines an ambiguous printing-picker resolution: re-ranks candidates by
  /// symbol similarity and promotes to `.auto` on a decisive, uncontradicted
  /// match. Any resolution it can't safely improve is returned unchanged.
  public func refine(
    _ resolution: ScryResolution,
    scan: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    lineMap: ScryLineMap? = nil,
    referenceImages: [String: CGImage],
    referenceCache: ScryFeaturePrintCache? = nil
  ) -> ScryResolution {
    guard resolution.confidence == .ambiguous,
          resolution.candidates.count >= 2,
          Self.isSingleNamePickerCase(resolution.candidates) else { return resolution }

    let upright = ScryTextExtractor.makeUpright(scan, orientation: orientation)
    let ranked = distances(
      scan: upright,
      scanBand: lineMap.map { ScrySymbolBand.scanBand(from: $0) },
      candidates: resolution.candidates,
      referenceImages: referenceImages,
      referenceCache: referenceCache
    )

    // Partial coverage: no basis to reorder (an unmeasured candidate would sink
    // for lacking an image, not for looking wrong).
    guard ranked.count == resolution.candidates.count, let best = ranked.first else {
      return resolution
    }

    var refined = resolution
    let byID = Dictionary(uniqueKeysWithValues: resolution.candidates.map { ($0.id, $0) })
    refined.candidates = ranked.compactMap { byID[$0.cardID] }

    let decisive = best.distance <= maxAcceptDistance
      && (ranked.count < 2 || ranked[1].distance >= best.distance * minRunnerUpRatio)
    guard decisive, let winner = byID[best.cardID] else { return refined }

    // A copyright year that disagrees with the visual winner means one of the
    // two signals mis-read — surface the picker rather than guess which.
    if let year = resolution.signals.copyrightYear,
       let releasedAt = winner.releasedAt,
       !releasedAt.hasPrefix(String(year)) {
      return refined
    }

    refined.card = winner
    refined.confidence = .auto
    refined.method = .nameAndVisual
    return refined
  }

  // MARK: - Internals

  /// All candidates are printings of the same card (the printing-picker case).
  static func isSingleNamePickerCase(_ candidates: [CardRecord]) -> Bool {
    guard let first = candidates.first else { return false }
    let key = first.name.normalizedQueryKey
    return candidates.allSatisfy { $0.name.normalizedQueryKey == key }
  }

  /// Crops a normalized top-left-origin band out of a card image.
  static func crop(_ image: CGImage, band: CGRect) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let rect = CGRect(
      x: band.origin.x * width,
      y: band.origin.y * height,
      width: band.width * width,
      height: band.height * height
    ).integral
    return image.cropping(to: rect)
  }

  static func featurePrint(of image: CGImage) throws -> VNFeaturePrintObservation {
    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    guard let observation = request.results?.first as? VNFeaturePrintObservation else {
      throw ScrySymbolMatchError.noFeaturePrint
    }
    return observation
  }
}

enum ScrySymbolMatchError: Error {
  case noFeaturePrint
}
#endif
