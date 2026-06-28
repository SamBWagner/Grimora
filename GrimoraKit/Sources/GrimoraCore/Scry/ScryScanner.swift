#if canImport(Vision)
import CoreGraphics
import Foundation
import Vision

/// The result of scanning one frame: which card was found, how it resolved, and
/// the rotation that read it.
public struct ScryScanResult: Sendable {
  public var resolution: ScryResolution
  public var detectedCard: ScryDetectedCard
  public var orientation: CGImagePropertyOrientation
}

/// End-to-end orchestrator: detect the fully-in-frame subject card, rectify it,
/// read it at the rotation that actually identifies a card, and resolve.
///
/// Rotation is resolved here rather than in the extractor because Vision reads
/// text at many angles — the only reliable "which way is up" signal is **which
/// rotation resolves to a real card in the database**. So the scanner tries the
/// four 90° rotations and keeps the best resolution (auto-accept > disambiguate
/// > nothing), stopping as soon as one auto-accepts.
public struct ScryScanner: Sendable {
  public var detector: ScryCardDetector
  public var extractor: ScryTextExtractor
  public let resolver: ScryCardResolver

  public init(
    database: CardDatabase,
    detector: ScryCardDetector = ScryCardDetector(),
    extractor: ScryTextExtractor = ScryTextExtractor()
  ) {
    self.detector = detector
    self.extractor = extractor
    self.resolver = ScryCardResolver(database: database)
  }

  /// Scans the most prominent fully-in-frame card. Returns `nil` only when no
  /// card could be locked in frame at all.
  public func scan(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> ScryScanResult? {
    guard let subject = try detector.detectSubject(in: image, orientation: orientation),
          let rectified = detector.rectify(image, card: subject) else {
      return nil
    }
    return try identify(rectified: rectified, detectedCard: subject)
  }

  /// A fast, best-effort identification for the live "what it thinks" readout:
  /// rectangles-only detection, a single orientation, no rotation search. Cheap
  /// enough to run a few times a second so the user can reposition before tapping.
  public func previewScan(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> ScryResolution? {
    guard let subject = try detector.detectCards(
      in: image,
      orientation: orientation,
      includeDocumentSegmentation: false
    ).first,
      let rectified = detector.rectify(image, card: subject) else {
      return nil
    }
    let signals = try extractor.extractSignals(from: rectified, orientation: .up)
    return try resolver.resolve(signals)
  }

  /// Reads an already-rectified card crop at the best rotation and resolves it.
  public func identify(
    rectified: CGImage,
    detectedCard: ScryDetectedCard
  ) throws -> ScryScanResult {
    var best: ScryScanResult?
    for orientation in [CGImagePropertyOrientation.up, .down, .right, .left] {
      let signals = try extractor.extractSignals(from: rectified, orientation: orientation)
      let resolution = try resolver.resolve(signals)
      let candidate = ScryScanResult(
        resolution: resolution,
        detectedCard: detectedCard,
        orientation: orientation
      )
      if best == nil || Self.rank(resolution) > Self.rank(best!.resolution) {
        best = candidate
      }
      if resolution.confidence == .auto { break }  // upright found — no need to keep rotating
    }
    // `best` is always set: the loop runs at least once.
    return best ?? ScryScanResult(
      resolution: .none(signals: ScrySignals()),
      detectedCard: detectedCard,
      orientation: .up
    )
  }

  private static func rank(_ resolution: ScryResolution) -> Int {
    switch resolution.confidence {
    case .auto: 3
    case .ambiguous: 2
    case .none: 1
    }
  }
}
#endif
