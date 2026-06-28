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
    onCards?(cards)
  }

  /// A still from the most recent frame, for the actual scan.
  func latestFrame() -> (image: CGImage, orientation: CGImagePropertyOrientation)? {
    lock.lock()
    let buffer = latestPixelBuffer
    lock.unlock()
    guard let buffer, let image = cgImage(from: buffer) else { return nil }
    return (image, orientation)
  }

  private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    return ciContext.createCGImage(ciImage, from: ciImage.extent)
  }
}
#endif
