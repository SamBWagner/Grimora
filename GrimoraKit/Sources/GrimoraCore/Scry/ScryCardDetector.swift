#if canImport(Vision)
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// One card-shaped rectangle found in the scene.
public struct ScryDetectedCard: Sendable, Equatable {
  /// Corners in Vision's normalized space (origin bottom-left): TL, TR, BR, BL.
  public var normalizedCorners: [CGPoint]
  /// Fraction of the image area the card occupies (used to pick the subject).
  public var areaFraction: Double
  /// Aspect ratio (shorter / longer side) of the detected quad.
  public var aspectRatio: Double
  public var confidence: Float
}

/// Finds the card to scan in a camera frame.
///
/// The contract the user asked for: only scan a card that is **fully in frame** —
/// one you can lock a complete rectangle around. Cards crossing the frame edge
/// (a neighbor poking in) and non-card objects (mouse, keyboard, cables) are
/// rejected, and the largest remaining card-shaped rectangle is the subject.
///
/// `rectify` perspective-corrects a detected card to a flat crop; the card may
/// still be rotated or upside down — `ScryTextExtractor.extractSignalsAutoOrientation`
/// sorts that out by reading whichever rotation parses.
public struct ScryCardDetector: Sendable {
  /// Vision's minimum shorter/longer side ratio (kept low to tolerate perspective).
  public var minimumAspectRatio: Float
  /// How far detected corners may deviate from 90° (tilt tolerance, max 45).
  public var quadratureTolerance: Float
  /// Minimum size as a fraction of the image's smaller dimension.
  public var minimumSize: Float
  public var minimumConfidence: VNConfidence
  public var maximumObservations: Int
  /// Corners must sit at least this far (fractional) inside every edge to count
  /// as "fully in frame". Kept small: its job is to reject a *neighbor card cut
  /// off by the frame* — whose cut corners clamp to ~0.000/1.000 — not a fully
  /// visible card that merely sits close to an edge (a large or tilted card on a
  /// bulk rig has a real corner ~1% from the frame, and a stricter margin
  /// wrongly rejected the whole card, leaving only its high-contrast text box).
  public var edgeMargin: Double
  /// Acceptable card aspect (shorter/longer). A Magic card is ~0.714; the range
  /// allows perspective foreshortening while still rejecting wide/odd shapes.
  public var cardAspectRange: ClosedRange<Double>

  public init(
    minimumAspectRatio: Float = 0.2,
    quadratureTolerance: Float = 45,
    minimumSize: Float = 0.08,
    minimumConfidence: VNConfidence = 0.3,
    maximumObservations: Int = 20,
    edgeMargin: Double = 0.008,
    cardAspectRange: ClosedRange<Double> = 0.5...0.92
  ) {
    self.minimumAspectRatio = minimumAspectRatio
    self.quadratureTolerance = quadratureTolerance
    self.minimumSize = minimumSize
    self.minimumConfidence = minimumConfidence
    self.maximumObservations = maximumObservations
    self.edgeMargin = edgeMargin
    self.cardAspectRange = cardAspectRange
  }

  /// Fully-in-frame, card-shaped rectangles, largest first.
  ///
  /// Runs both `VNDetectRectanglesRequest` (good for multiple cards) and
  /// `VNDetectDocumentSegmentationRequest` (more robust for a single steeply-
  /// angled card), merges the candidates, and dedupes near-duplicates.
  public func detectCards(
    in image: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    includeDocumentSegmentation: Bool = true
  ) throws -> [ScryDetectedCard] {
    let rectangles = VNDetectRectanglesRequest()
    rectangles.minimumAspectRatio = minimumAspectRatio
    rectangles.quadratureTolerance = quadratureTolerance
    rectangles.minimumSize = minimumSize
    rectangles.minimumConfidence = minimumConfidence
    rectangles.maximumObservations = maximumObservations

    // Document segmentation is the robust fallback for steeply-angled cards but is
    // heavier, so the live preview (per-frame) skips it; the actual scan keeps it.
    var requests: [VNRequest] = [rectangles]
    let documentSegmentation = VNDetectDocumentSegmentationRequest()
    if includeDocumentSegmentation { requests.append(documentSegmentation) }

    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
    try handler.perform(requests)

    let width = Double(image.width)
    let height = Double(image.height)

    func card(from observation: VNRectangleObservation) -> ScryDetectedCard? {
      let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]

      // Fully in frame: every corner comfortably inside all four edges.
      guard corners.allSatisfy({ corner in
        corner.x >= edgeMargin && corner.x <= 1 - edgeMargin
          && corner.y >= edgeMargin && corner.y <= 1 - edgeMargin
      }) else { return nil }

      // Card-shaped: convert to pixels (aspect is distorted in normalized space).
      let pixels = corners.map { CGPoint(x: $0.x * width, y: $0.y * height) }
      let aspect = Self.aspectRatio(of: pixels)
      guard cardAspectRange.contains(aspect) else { return nil }

      let area = Self.polygonArea(pixels) / (width * height)
      return ScryDetectedCard(
        normalizedCorners: corners,
        areaFraction: area,
        aspectRatio: aspect,
        confidence: observation.confidence
      )
    }

    let rectangleCards = (rectangles.results ?? []).compactMap(card(from:))
    // Document segmentation is a FALLBACK for steeply-angled single cards, not a
    // co-equal source: its region can swell to swallow an overlapping neighbor —
    // a bigger, still card-shaped quad that beats the tight rectangle and makes
    // OCR read the neighbor's title (a real cluttered scene picked up "Arch of
    // Orazca" beneath the Terastodon this way). So keep only doc-seg regions that
    // no rectangle already covers.
    let documentCards = includeDocumentSegmentation
      ? (documentSegmentation.results ?? []).compactMap(card(from:))
      : []
    let rectangleCentroids = rectangleCards.map { Self.centroid($0.normalizedCorners) }
    let documentFallback = documentCards.filter { document in
      let center = Self.centroid(document.normalizedCorners)
      return !rectangleCentroids.contains { hypot($0.x - center.x, $0.y - center.y) < 0.06 }
    }

    return Self.deduplicated((rectangleCards + documentFallback).sorted { $0.areaFraction > $1.areaFraction })
  }

  /// Drops near-duplicate detections (the two requests often find the same card),
  /// keeping the largest of each cluster.
  static func deduplicated(_ cards: [ScryDetectedCard]) -> [ScryDetectedCard] {
    var kept: [ScryDetectedCard] = []
    for card in cards {
      let center = centroid(card.normalizedCorners)
      let isDuplicate = kept.contains { existing in
        hypot(centroid(existing.normalizedCorners).x - center.x,
               centroid(existing.normalizedCorners).y - center.y) < 0.06
      }
      if !isDuplicate { kept.append(card) }
    }
    return kept
  }

  static func centroid(_ points: [CGPoint]) -> CGPoint {
    let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    let count = CGFloat(points.count)
    return CGPoint(x: sum.x / count, y: sum.y / count)
  }

  /// The most prominent fully-in-frame card — the one to scan.
  public func detectSubject(
    in image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> ScryDetectedCard? {
    try detectCards(in: image, orientation: orientation).first
  }

  /// Perspective-corrects a detected card to a flat crop (orientation unresolved).
  public func rectify(_ image: CGImage, card: ScryDetectedCard) -> CGImage? {
    let ciImage = CIImage(cgImage: image)
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    func point(_ corner: CGPoint) -> CGPoint {
      CGPoint(x: corner.x * width, y: corner.y * height)  // normalized & CIImage share bottom-left origin
    }

    let filter = CIFilter.perspectiveCorrection()
    filter.inputImage = ciImage
    filter.topLeft = point(card.normalizedCorners[0])
    filter.topRight = point(card.normalizedCorners[1])
    filter.bottomRight = point(card.normalizedCorners[2])
    filter.bottomLeft = point(card.normalizedCorners[3])

    guard let output = filter.outputImage else { return nil }
    return CIContext(options: nil).createCGImage(output, from: output.extent)
  }

  // MARK: - Geometry

  /// Shorter / longer side, averaging opposite edges of the quad (TL, TR, BR, BL).
  static func aspectRatio(of quad: [CGPoint]) -> Double {
    let top = distance(quad[0], quad[1])
    let bottom = distance(quad[3], quad[2])
    let left = distance(quad[0], quad[3])
    let right = distance(quad[1], quad[2])
    let horizontal = (top + bottom) / 2
    let vertical = (left + right) / 2
    let longer = Swift.max(horizontal, vertical)
    guard longer > 0 else { return 0 }
    return Swift.min(horizontal, vertical) / longer
  }

  static func polygonArea(_ quad: [CGPoint]) -> Double {
    var sum = 0.0
    for index in quad.indices {
      let a = quad[index]
      let b = quad[(index + 1) % quad.count]
      sum += Double(a.x * b.y - b.x * a.y)
    }
    return abs(sum) / 2
  }

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    Double(hypot(a.x - b.x, a.y - b.y))
  }
}
#endif
