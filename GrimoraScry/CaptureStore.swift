import CoreGraphics
import Foundation
import GrimoraCore
import ImageIO
import UniformTypeIdentifiers

/// One labeled capture — the sidecar JSON schema that
/// `Tools/scry_import_captures.py` reads when merging captures into the corpus.
struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
  struct CardIdentity: Codable, Equatable, Sendable {
    var name: String
    var setCode: String
    var collectorNumber: String

    init(name: String, setCode: String, collectorNumber: String) {
      self.name = name
      self.setCode = setCode
      self.collectorNumber = collectorNumber
    }

    init(_ card: CardRecord) {
      self.init(name: card.name, setCode: card.setCode, collectorNumber: card.collectorNumber)
    }
  }

  struct EngineOutcome: Codable, Equatable, Sendable {
    var confidence: String
    var method: String
    var card: CardIdentity?
    var candidates: [CardIdentity]
    var signalName: String?
    var signalSetCode: String?
    var signalCollectorNumber: String?
    var signalSetTotal: Int?
    var rawTextLines: [String]

    init(_ resolution: ScryResolution) {
      confidence = resolution.confidence.rawValue
      method = resolution.method.rawValue
      card = resolution.card.map(CardIdentity.init)
      candidates = resolution.candidates.map(CardIdentity.init)
      signalName = resolution.signals.name
      signalSetCode = resolution.signals.setCode
      signalCollectorNumber = resolution.signals.collectorNumber
      signalSetTotal = resolution.signals.setTotal
      rawTextLines = resolution.signals.rawTextLines
    }
  }

  struct CaptureMeta: Codable, Equatable, Sendable {
    /// "still" or "videoFrame" — a video-frame fallback explains a low-res entry.
    var source: String
    var exifOrientation: UInt32
    var deviceModel: String
    var systemVersion: String
  }

  enum Verdict: String, Codable, Sendable {
    /// The engine's auto-accepted card was the right printing.
    case correct
    /// The engine failed: wrong auto-accept, correct card missing from
    /// candidates, or unresolved. Imports as a `knownFailure` corpus entry.
    case wrong
    /// Saved without a verdict; skipped by the importer until labeled.
    case skipped
  }

  var schemaVersion: Int
  var id: String
  var timestamp: Date
  var verdict: Verdict
  /// The engine was ambiguous and the right card was among its candidates —
  /// imports as a `disambiguation` corpus entry rather than `auto`.
  var pickedFromCandidates: Bool
  var needsLabel: Bool
  var groundTruth: CardIdentity?
  var foil: Bool
  var sleeved: Bool
  var background: String
  var notes: String?
  var engine: EngineOutcome?
  var capture: CaptureMeta
}

/// Writes captures into Documents/Captures. That folder is the entire export
/// story: UIFileSharingEnabled makes it visible under the phone in Finder, and
/// dragging it out feeds `Tools/scry_import_captures.py`.
struct CaptureStore: Sendable {
  let root: URL

  static func documents(fileManager: FileManager = .default) -> CaptureStore {
    let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return CaptureStore(root: documents.appendingPathComponent("Captures", isDirectory: true))
  }

  static func makeID(date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = String(format: "%04x", UInt16.random(in: .min ... .max))
    return "\(formatter.string(from: date))-\(suffix)"
  }

  func sidecarURL(for id: String) -> URL { root.appendingPathComponent("\(id).json") }
  func stillURL(for id: String) -> URL { root.appendingPathComponent("\(id)-still.jpg") }
  func cropURL(for id: String) -> URL { root.appendingPathComponent("\(id)-crop.jpg") }

  /// Writes the sidecar plus the still (EXIF orientation preserved) and the
  /// upright-baked crop when present.
  func save(
    record: CaptureRecord,
    still: CGImage?,
    stillOrientation: CGImagePropertyOrientation,
    crop: CGImage?
  ) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if let still {
      try Self.writeJPEG(still, orientation: stillOrientation, to: stillURL(for: record.id))
    }
    if let crop {
      try Self.writeJPEG(crop, orientation: .up, to: cropURL(for: record.id))
    }
    try write(record: record)
  }

  /// Rewrites just the sidecar — for re-verdicts and relabels.
  func write(record: CaptureRecord) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(record).write(to: sidecarURL(for: record.id), options: .atomic)
  }

  /// All saved captures, newest first. Unreadable sidecars are skipped.
  func listRecords() -> [CaptureRecord] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let sidecars = (try? FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil
    )) ?? []
    return sidecars
      .filter { $0.pathExtension == "json" }
      .compactMap { url in
        (try? Data(contentsOf: url)).flatMap { try? decoder.decode(CaptureRecord.self, from: $0) }
      }
      .sorted { $0.timestamp > $1.timestamp }
  }

  func delete(id: String) {
    for url in [sidecarURL(for: id), stillURL(for: id), cropURL(for: id)] {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// A small preview of the crop (falling back to the still), EXIF applied.
  func thumbnail(for id: String, maxPixel: Int = 240) -> CGImage? {
    for url in [cropURL(for: id), stillURL(for: id)] {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
      ]
      if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
        return thumbnail
      }
    }
    return nil
  }

  private static func writeJPEG(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation,
    to url: URL
  ) throws {
    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: 0.9,
      kCGImagePropertyOrientation: orientation.rawValue,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
