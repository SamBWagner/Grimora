#if os(iOS)
import AVFoundation
import CoreGraphics
import ImageIO

/// One-shot high-resolution still capture for the full identification scan.
///
/// The live video feed (1080p) is plenty for detection and the preview guess,
/// but the tiny collector line on old frames needs more pixels than a video
/// frame gives a card that isn't filling the frame. A 12MP still turns a
/// card at ~40% of frame height from a ~500px crop into a ~1500–2100px one —
/// comfortably above the OCR floor — and is only paid at scan time.
///
/// Use one instance per capture: the object is its own delegate and must stay
/// alive until the callback fires, which `capture(from:on:)` guarantees by
/// holding `self` in the continuation.
final class ScryStillCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
  enum CaptureError: Error {
    case noImage
  }

  private let output: AVCapturePhotoOutput
  private let sessionQueue: DispatchQueue
  private var continuation: CheckedContinuation<(image: CGImage, orientation: CGImagePropertyOrientation), Error>?

  init(output: AVCapturePhotoOutput, sessionQueue: DispatchQueue) {
    self.output = output
    self.sessionQueue = sessionQueue
  }

  /// Captures one still and returns it with its EXIF orientation (the CGImage
  /// itself is unrotated sensor data; `ScryScanner` applies the orientation).
  func capture() async throws -> (image: CGImage, orientation: CGImagePropertyOrientation) {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      sessionQueue.async { [self] in
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        // .balanced favors capture speed over maximum fidelity — right for OCR —
        // but the setting may not exceed the output's configured maximum.
        let balanced = AVCapturePhotoOutput.QualityPrioritization.balanced
        let maximum = output.maxPhotoQualityPrioritization
        settings.photoQualityPrioritization = maximum.rawValue < balanced.rawValue ? maximum : balanced
        output.capturePhoto(with: settings, delegate: self)
      }
    }
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    guard let continuation else { return }
    self.continuation = nil

    if let error {
      continuation.resume(throwing: error)
      return
    }
    guard let image = photo.cgImageRepresentation() else {
      continuation.resume(throwing: CaptureError.noImage)
      return
    }
    continuation.resume(returning: (image, Self.orientation(of: photo)))
  }

  /// The EXIF orientation from the photo's metadata; a back camera held in
  /// portrait produces `.right`, which is also the sensible fallback.
  static func orientation(of photo: AVCapturePhoto) -> CGImagePropertyOrientation {
    if let raw = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
       let parsed = CGImagePropertyOrientation(rawValue: raw) {
      return parsed
    }
    return .right
  }
}
#endif
