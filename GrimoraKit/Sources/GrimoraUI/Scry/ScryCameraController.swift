#if os(iOS)
import AVFoundation
import CoreGraphics
import GrimoraCore
import Observation
import SwiftUI

/// Owns the camera session for the Scry tab: permissions, the live preview feed,
/// the live card detections that drive the overlay, and the on-demand scan.
@MainActor
@Observable
final class ScryCameraController {
  enum Authorization: Equatable {
    case undetermined
    case authorized
    case denied
  }

  /// A running best guess of the card in view, for the "what it thinks" readout
  /// and for bulk auto-add.
  struct PreviewGuess: Equatable, Sendable {
    /// The resolved printing, present only when `confident`.
    var card: CardRecord?
    var name: String
    /// True when the guess is confident enough that a scan would auto-accept it.
    var confident: Bool
  }

  private(set) var authorization: Authorization = ScryCameraController.currentAuthorization()
  private(set) var isRunning = false
  /// Live detections (normalized, raw-buffer space) for the preview overlay.
  private(set) var detectedCards: [ScryDetectedCard] = []
  /// The live best guess, refreshed a few times a second while a card is locked.
  private(set) var previewGuess: PreviewGuess?
  /// Increments every preview cycle — even when the guess is unchanged — so
  /// observers can run per-cycle logic (e.g. bulk stability) that `onChange(of:
  /// previewGuess)` would miss, since that only fires when the value changes.
  private(set) var previewGeneration = 0

  private var previewTask: Task<Void, Never>?

  let session = AVCaptureSession()

  private let sessionQueue = DispatchQueue(label: "com.samwagner.Grimora.scry.session")
  private let videoQueue = DispatchQueue(label: "com.samwagner.Grimora.scry.video")
  private let videoOutput = AVCaptureVideoDataOutput()
  private let processor: ScryFrameProcessor
  private var isConfigured = false
  private var scanner: ScryScanner?
  private var device: AVCaptureDevice?

  init(detector: ScryCardDetector = ScryCardDetector()) {
    processor = ScryFrameProcessor(detector: detector)
    processor.onCards = { [weak self] cards in
      Task { @MainActor in self?.detectedCards = cards }
    }
  }

  // MARK: - Lifecycle

  /// Requests permission if needed, configures the session once, and starts it.
  func start(database: CardDatabase) async {
    if scanner == nil {
      scanner = ScryScanner(database: database)
    }
    await requestAuthorizationIfNeeded()
    guard authorization == .authorized else { return }

    sessionQueue.async { [self] in
      configureIfNeeded()
      if !session.isRunning {
        session.startRunning()
      }
      let running = session.isRunning
      Task { @MainActor in
        self.isRunning = running
        self.startPreviewLoop()
      }
    }
  }

  func stop() {
    detectedCards = []
    previewGuess = nil
    previewTask?.cancel()
    previewTask = nil
    sessionQueue.async { [self] in
      if session.isRunning {
        session.stopRunning()
      }
      Task { @MainActor in self.isRunning = false }
    }
  }

  // MARK: - Live preview guess

  private func startPreviewLoop() {
    guard previewTask == nil else { return }
    previewTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.refreshPreviewGuess()
        try? await Task.sleep(for: .milliseconds(650))
      }
    }
  }

  private func refreshPreviewGuess() async {
    defer { previewGeneration &+= 1 }
    guard !detectedCards.isEmpty, let scanner else {
      previewGuess = nil
      return
    }
    let processor = self.processor
    previewGuess = await Task.detached(priority: .utility) { () -> PreviewGuess? in
      guard let frame = processor.latestFrame(),
            let resolution = try? scanner.previewScan(frame.image, orientation: frame.orientation) else {
        return nil
      }
      switch resolution.confidence {
      case .auto:
        return resolution.card.map { PreviewGuess(card: $0, name: $0.name, confident: true) }
      case .ambiguous:
        return resolution.candidates.first.map { PreviewGuess(card: nil, name: $0.name, confident: false) }
      case .none:
        return nil
      }
    }.value
  }

  // MARK: - Scanning

  /// Grabs the latest frame and runs the full identification pipeline off the main
  /// actor. Returns `nil` when no card could be locked in frame.
  func scan() async -> ScryScanResult? {
    guard let scanner else { return nil }
    let processor = self.processor
    return await Task.detached(priority: .userInitiated) {
      guard let frame = processor.latestFrame() else { return nil }
      return try? scanner.scan(frame.image, orientation: frame.orientation)
    }.value
  }

  // MARK: - Authorization

  private func requestAuthorizationIfNeeded() async {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      authorization = .authorized
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      authorization = granted ? .authorized : .denied
    default:
      authorization = .denied
    }
  }

  private static func currentAuthorization() -> Authorization {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: .authorized
    case .notDetermined: .undetermined
    default: .denied
    }
  }

  // MARK: - Configuration

  /// Runs on `sessionQueue`.
  private func configureIfNeeded() {
    guard !isConfigured else { return }
    session.beginConfiguration()
    session.sessionPreset = .high

    if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
       let input = try? AVCaptureDeviceInput(device: device),
       session.canAddInput(input) {
      session.addInput(input)
      self.device = device
      configureForFocus(device)
    }

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    videoOutput.setSampleBufferDelegate(processor, queue: videoQueue)
    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
    }

    session.commitConfiguration()
    isConfigured = true
  }

  private func configureForFocus(_ device: AVCaptureDevice) {
    guard (try? device.lockForConfiguration()) != nil else { return }
    // Bias focus and metering to the center, where the card sits — keeps the
    // camera from focusing on the box walls / background instead of the card.
    let center = CGPoint(x: 0.5, y: 0.5)
    if device.isFocusPointOfInterestSupported {
      device.focusPointOfInterest = center
    }
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    if device.isAutoFocusRangeRestrictionSupported {
      device.autoFocusRangeRestriction = .near  // cards are held close
    }
    if device.isSmoothAutoFocusSupported {
      device.isSmoothAutoFocusEnabled = true
    }
    if device.isExposurePointOfInterestSupported {
      device.exposurePointOfInterest = center
    }
    device.unlockForConfiguration()
  }

  // MARK: - Focus control (for the fixed bulk-scan rig)

  /// Locks focus and exposure at the current setting so cards placed at the same
  /// spot stay sharp instead of the camera re-hunting on each one.
  func setFocusLocked(_ locked: Bool) {
    sessionQueue.async { [self] in
      guard let device, (try? device.lockForConfiguration()) != nil else { return }
      if locked {
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
      } else {
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
      }
      device.unlockForConfiguration()
    }
  }

  /// Tap-to-focus: focus and meter at a point in the camera's device coordinate
  /// space (origin top-left, normalized), then re-lock in bulk or resume
  /// continuous autofocus otherwise. Fixes focus drifting and getting stuck soft.
  func focus(atDevicePoint point: CGPoint, lock: Bool) {
    sessionQueue.async { [self] in
      guard let device, (try? device.lockForConfiguration()) != nil else { return }
      if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
      }
      if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
        device.exposurePointOfInterest = point
        device.exposureMode = .autoExpose
      }
      device.unlockForConfiguration()
    }
    // Let the one-shot focus settle, then lock (bulk) or hand back to continuous AF.
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.7))
      self.setFocusLocked(lock)
    }
  }

  /// One-shot refocus on the center, then relock — for when the rig is repositioned.
  func refocusThenLock() {
    sessionQueue.async { [self] in
      guard let device, (try? device.lockForConfiguration()) != nil else { return }
      let center = CGPoint(x: 0.5, y: 0.5)
      if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
        device.focusPointOfInterest = center
        device.focusMode = .autoFocus
      }
      if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
        device.exposurePointOfInterest = center
        device.exposureMode = .autoExpose
      }
      device.unlockForConfiguration()
    }
    // Give the one-shot autofocus a moment to settle, then lock it.
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.0))
      self.setFocusLocked(true)
    }
  }
}
#endif
