#if os(iOS)
import AVFoundation
import GrimoraCore
import SwiftUI
import UIKit

/// The live camera preview with an overlay that draws a "lock" around each
/// detected fully-in-frame card.
public struct ScryCameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  let detectedCards: [ScryDetectedCard]
  var lockColor: UIColor
  /// Tap-to-focus callback, given a point in the camera's device coordinate space.
  var onFocusTap: ((CGPoint) -> Void)? = nil

  public init(
    session: AVCaptureSession,
    detectedCards: [ScryDetectedCard],
    lockColor: UIColor = .scryLock,
    onFocusTap: ((CGPoint) -> Void)? = nil
  ) {
    self.session = session
    self.detectedCards = detectedCards
    self.lockColor = lockColor
    self.onFocusTap = onFocusTap
  }

  public func makeUIView(context: Context) -> ScryPreviewUIView {
    let view = ScryPreviewUIView()
    view.previewLayer.session = session
    view.lockColor = lockColor
    view.onFocusTap = onFocusTap
    return view
  }

  public func updateUIView(_ uiView: ScryPreviewUIView, context: Context) {
    uiView.lockColor = lockColor
    uiView.onFocusTap = onFocusTap
    uiView.update(cards: detectedCards)
  }
}

/// A view backed by `AVCaptureVideoPreviewLayer`, with a shape layer that draws
/// the detected card quads (Vision normalized corners → preview-layer points).
public final class ScryPreviewUIView: UIView {
  public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

  var lockColor: UIColor = .scryLock
  /// Called with a device-space point when the user taps to focus.
  var onFocusTap: ((CGPoint) -> Void)?

  private let overlayLayer = CAShapeLayer()
  private var cards: [ScryDetectedCard] = []

  public override init(frame: CGRect) {
    super.init(frame: frame)
    previewLayer.videoGravity = .resizeAspectFill
    overlayLayer.fillColor = UIColor.clear.cgColor
    overlayLayer.lineWidth = 3
    overlayLayer.lineJoin = .round
    layer.addSublayer(overlayLayer)

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
    tap.cancelsTouchesInView = false  // let SwiftUI controls keep working
    addGestureRecognizer(tap)
  }

  @objc private func handleFocusTap(_ recognizer: UITapGestureRecognizer) {
    let location = recognizer.location(in: self)
    let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
    onFocusTap?(devicePoint)
    showFocusReticle(at: location)
  }

  private func showFocusReticle(at point: CGPoint) {
    let size: CGFloat = 72
    let reticle = CAShapeLayer()
    reticle.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
    reticle.path = UIBezierPath(
      roundedRect: CGRect(origin: .zero, size: CGSize(width: size, height: size)),
      cornerRadius: 6
    ).cgPath
    reticle.strokeColor = lockColor.cgColor
    reticle.fillColor = UIColor.clear.cgColor
    reticle.lineWidth = 1.5
    layer.addSublayer(reticle)

    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = 1.35
    scale.toValue = 1.0
    scale.duration = 0.25

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1.0
    fade.toValue = 0.0
    fade.beginTime = CACurrentMediaTime() + 0.5
    fade.duration = 0.35
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false

    reticle.add(scale, forKey: "scale")
    reticle.add(fade, forKey: "fade")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { reticle.removeFromSuperlayer() }
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  func update(cards: [ScryDetectedCard]) {
    self.cards = cards
    redraw()
  }

  public override func layoutSublayers(of layer: CALayer) {
    super.layoutSublayers(of: layer)
    overlayLayer.frame = bounds
    redraw()
  }

  private func redraw() {
    overlayLayer.strokeColor = lockColor.cgColor
    // Draw a single clean rectangle around the subject (largest) card only —
    // the detector also surfaces smaller inner rectangles (the art box) that
    // would clutter the overlay.
    guard let card = cards.first else {
      overlayLayer.path = nil
      return
    }
    let points = card.normalizedCorners.map { previewPoint(for: $0) }
    guard points.count == 4 else {
      overlayLayer.path = nil
      return
    }
    let path = UIBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    path.close()
    overlayLayer.path = path.cgPath
  }

  /// Vision uses a bottom-left origin; the preview layer's device-point conversion
  /// expects a top-left origin, so flip Y.
  private func previewPoint(for normalizedCorner: CGPoint) -> CGPoint {
    let devicePoint = CGPoint(x: normalizedCorner.x, y: 1 - normalizedCorner.y)
    return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
  }
}

extension UIColor {
  /// Pale grimoire purple — the app's dark-mode accent (GrimoraPalette), used for
  /// the Scry lock overlay over the camera feed.
  public static let scryLock = UIColor(red: 0.735, green: 0.610, blue: 0.820, alpha: 1.0)
}
#endif
