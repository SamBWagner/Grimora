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
  /// The rectified card crop the signals were read from, kept so an ambiguous
  /// resolution can be refined afterwards (`ScrySymbolMatcher`) without
  /// re-detecting. Read it with `orientation` applied.
  public var rectified: CGImage?
  /// The text geometry of the winning orientation's read — anchors the symbol
  /// band for refinement.
  public var lineMap: ScryLineMap?
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

  /// OCR level for the live preview loop only. `.accurate` by default — bulk
  /// mode commits straight off preview guesses, so preview quality is
  /// precision-relevant there. `.fast` is an available experiment for flows
  /// whose commit path always re-reads with a full scan.
  public var previewRecognitionLevel: VNRequestTextRecognitionLevel

  public init(
    database: CardDatabase,
    detector: ScryCardDetector = ScryCardDetector(),
    extractor: ScryTextExtractor = ScryTextExtractor(),
    previewRecognitionLevel: VNRequestTextRecognitionLevel = .accurate
  ) {
    self.detector = detector
    self.extractor = extractor
    self.resolver = ScryCardResolver(database: database)
    self.previewRecognitionLevel = previewRecognitionLevel
  }

  /// Scans the most prominent fully-in-frame card. Returns `nil` only when no
  /// card could be locked in frame at all. `tryFirst` reorders the rotation
  /// search (orientation memory: cards on a rig tend to stay oriented the same
  /// way, and the right first guess makes most scans a single OCR pass).
  public func scan(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    tryFirst: CGImagePropertyOrientation? = nil
  ) throws -> ScryScanResult? {
    // Vision reports detection corners in the ORIENTED image space, while
    // `rectify` maps corners onto the raw pixels — with a non-.up orientation
    // (a 12MP still carries EXIF .right) the quad lands in the wrong place and
    // the "card" comes out as a clipped, skewed fragment. Baking the
    // orientation into the pixels first keeps every consumer in one space.
    let upright = ScryTextExtractor.makeUpright(image, orientation: orientation)
    guard let subject = try detector.detectSubject(in: upright, orientation: .up),
          let rectified = detector.rectify(upright, card: subject) else {
      return nil
    }
    return try identify(rectified: rectified, detectedCard: subject, tryFirst: tryFirst)
  }

  /// A fast, best-effort identification for the live "what it thinks" readout:
  /// rectangles-only detection (skipped entirely when the caller already has a
  /// consistent live quad to seed with), a single orientation, no rotation
  /// search. Cheap enough to run a few times a second so the user can reposition
  /// before tapping.
  public func previewScan(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    seedCard: ScryDetectedCard? = nil,
    readingOrientation: CGImagePropertyOrientation = .up
  ) throws -> ScryResolution? {
    // Same coordinate rule as `scan`: corners live in the oriented space (a
    // seed quad was detected at this same orientation), so bake the pixels
    // upright and rectify there. No-op for the common .up video frame.
    let upright = ScryTextExtractor.makeUpright(image, orientation: orientation)
    let subject: ScryDetectedCard
    if let seedCard {
      subject = seedCard
    } else if let detected = try detector.detectCards(
      in: upright,
      orientation: .up,
      includeDocumentSegmentation: false
    ).first {
      subject = detected
    } else {
      return nil
    }
    guard let rectified = detector.rectify(upright, card: subject) else {
      return nil
    }
    // No bottom-strip retry here: the preview loop runs a few times a second and
    // the retry would double its OCR cost exactly when no card is locked yet.
    var previewExtractor = extractor
    previewExtractor.usesBottomStripRetry = false
    previewExtractor.recognitionLevel = previewRecognitionLevel
    let signals = try previewExtractor.extractSignals(from: rectified, orientation: readingOrientation)
    let resolution = try resolver.resolve(signals)
    // Orientation memory can go stale (a sideways split card sets it, the next
    // card sits upright) — a dead read at a remembered rotation self-heals by
    // retrying upright rather than leaving the preview blind.
    if resolution.confidence == .none, readingOrientation != .up {
      let upright = try previewExtractor.extractSignals(from: rectified, orientation: .up)
      return try resolver.resolve(upright)
    }
    return resolution
  }

  /// Reads an already-rectified card crop at the best rotation and resolves it.
  /// `tryFirst` moves a remembered orientation to the front of the rotation
  /// search, so a correctly-remembered rig usually pays one OCR pass, not four.
  public func identify(
    rectified: CGImage,
    detectedCard: ScryDetectedCard,
    tryFirst: CGImagePropertyOrientation? = nil
  ) throws -> ScryScanResult {
    var orientations: [CGImagePropertyOrientation] = [.up, .down, .right, .left]
    if let tryFirst, let index = orientations.firstIndex(of: tryFirst), index != 0 {
      orientations.remove(at: index)
      orientations.insert(tryFirst, at: 0)
    }

    var best: ScryScanResult?
    var perOrientationSignals: [ScrySignals] = []
    for orientation in orientations {
      let extraction = try extractor.extract(from: rectified, orientation: orientation)
      perOrientationSignals.append(extraction.signals)
      let resolution = try resolver.resolve(extraction.signals)
      let candidate = ScryScanResult(
        resolution: resolution,
        detectedCard: detectedCard,
        orientation: orientation,
        rectified: rectified,
        lineMap: extraction.lineMap
      )
      if best == nil || Self.rank(resolution) > Self.rank(best!.resolution) {
        best = candidate
      }
      if resolution.confidence == .auto { break }  // upright found — no need to keep rotating
    }

    // Cross-orientation assist for rotated layouts. A split card's names read
    // sideways while its collector line reads upright, so no single rotation
    // carries every signal — merge the fields across rotations and try once
    // more. Precision gate: only a printed-key resolution (exact key, or name +
    // collector number) may auto-accept from merged signals; name-only evidence
    // stitched across rotations is not trusted.
    if var current = best, current.resolution.confidence != .auto,
       let merged = Self.mergedSignals(from: perOrientationSignals) {
      let resolution = try resolver.resolve(merged)
      if resolution.confidence == .auto,
         resolution.method == .exactKey || resolution.method == .nameAndNumber {
        current.resolution = resolution
        return current
      }
    }

    // `best` is always set: the loop runs at least once.
    return best ?? ScryScanResult(
      resolution: .none(signals: ScrySignals()),
      detectedCard: detectedCard,
      orientation: .up,
      rectified: rectified,
      lineMap: nil
    )
  }

  /// Field-wise union of the per-rotation reads (first rotation that produced a
  /// field wins), or `nil` when no single field would be new — i.e. some
  /// rotation already saw the whole combination, so re-resolving adds nothing.
  static func mergedSignals(from perOrientation: [ScrySignals]) -> ScrySignals? {
    let merged = ScrySignals(
      name: perOrientation.compactMap(\.name).first,
      setCode: perOrientation.compactMap(\.setCode).first,
      collectorNumber: perOrientation.compactMap(\.collectorNumber).first,
      setTotal: perOrientation.compactMap(\.setTotal).first,
      copyrightYear: perOrientation.compactMap(\.copyrightYear).first,
      colors: [],
      rawTextLines: perOrientation.flatMap(\.rawTextLines)
    )
    let alreadyTried = perOrientation.contains {
      $0.name == merged.name
        && $0.setCode == merged.setCode
        && $0.collectorNumber == merged.collectorNumber
    }
    return alreadyTried ? nil : merged
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
