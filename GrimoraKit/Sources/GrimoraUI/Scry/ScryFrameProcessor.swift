#if os(iOS)
import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import GrimoraCore

/// Receives camera frames on a background queue, runs lightweight live card
/// detection (throttled) for the preview overlay, and keeps the most recent frame
/// so a scan can grab a still on demand.
///
/// `@unchecked Sendable` with an internal lock: the AVFoundation delegate callback
/// is nonisolated and hops between queues, so the shared state is lock-guarded.
final class ScryFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
  private let detector: ScryCardDetector
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  private let lock = NSLock()
  private var latestPixelBuffer: CVPixelBuffer?
  /// The buffer the most recent live detection ran on, with its results — kept
  /// as a pair so `latestFrame()` can hand out quads that are geometrically
  /// consistent with the image (at most one detection interval stale).
  private var latestDetectedBuffer: CVPixelBuffer?
  private var latestDetectedCards: [ScryDetectedCard] = []
  private var lastDetection = Date.distantPast

  /// Minimum gap between live-detection passes (the preview doesn't need 30fps).
  var detectionInterval: TimeInterval = 0.18

  /// Everything runs in the raw buffer's coordinate space; the scan's identify
  /// step resolves the card's true rotation, so live detection stays orientation-
  /// agnostic and the overlay maps cleanly to the preview layer.
  let orientation: CGImagePropertyOrientation = .up

  /// Called on a background queue with the latest live detections (normalized).
  var onCards: (@Sendable ([ScryDetectedCard]) -> Void)?

  init(detector: ScryCardDetector) {
    self.detector = detector
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lock.lock()
    latestPixelBuffer = pixelBuffer
    lock.unlock()

    let now = Date()
    guard now.timeIntervalSince(lastDetection) >= detectionInterval else { return }
    lastDetection = now

    guard let image = cgImage(from: pixelBuffer) else { return }
    let cards = (try? detector.detectCards(
      in: image,
      orientation: orientation,
      includeDocumentSegmentation: false
    )) ?? []
    lock.lock()
    latestDetectedBuffer = pixelBuffer
    latestDetectedCards = cards
    lock.unlock()
    onCards?(cards)
  }

  /// The most recent frame, preferring the one whose live detections are known
  /// so callers can reuse the quads without re-detecting. `cards` is empty when
  /// only an undetected (newer) frame is available.
  func latestFrame() -> (image: CGImage, orientation: CGImagePropertyOrientation, cards: [ScryDetectedCard])? {
    lock.lock()
    let buffer = latestDetectedBuffer ?? latestPixelBuffer
    let cards = latestDetectedBuffer != nil ? latestDetectedCards : []
    lock.unlock()
    guard let buffer, let image = cgImage(from: buffer) else { return nil }
    return (image, orientation, cards)
  }

  private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    return ciContext.createCGImage(ciImage, from: ciImage.extent)
  }
}
#endif
