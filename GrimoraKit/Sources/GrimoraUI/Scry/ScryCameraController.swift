#if os(iOS)
import AVFoundation
import CoreGraphics
import GrimoraCore
import ImageIO
import Observation
import SwiftUI

/// A scan plus the exact input image it ran on, so a harness can archive the
/// original capture alongside the recognition outcome.
public struct ScryScanCapture: Sendable {
  public enum Source: String, Sendable {
    /// High-resolution photo capture.
    case still
    /// The latest preview video frame (still capture skipped, failed, or timed out).
    case videoFrame
  }

  /// The pipeline's outcome; `nil` when no card could be locked.
  public var result: ScryScanResult?
  /// The unrotated sensor image the pipeline read (pair with `orientation`).
  public var image: CGImage?
  public var orientation: CGImagePropertyOrientation
  public var source: Source
}

/// Owns the camera session for the Scry tab: permissions, the live preview feed,
/// the live card detections that drive the overlay, and the on-demand scan.
@MainActor
@Observable
public final class ScryCameraController {
  public enum Authorization: Equatable {
    case undetermined
    case authorized
    case denied
  }

  /// A running best guess of the card in view, for the "what it thinks" readout
  /// and for bulk auto-add.
  public struct PreviewGuess: Equatable, Sendable {
    /// The resolved printing, present only when `confident`.
    public var card: CardRecord?
    public var name: String
    /// True when the guess is confident enough that a scan would auto-accept it.
    public var confident: Bool
  }

  public private(set) var authorization: Authorization = ScryCameraController.currentAuthorization()
  public private(set) var isRunning = false
  /// Live detections (normalized, raw-buffer space) for the preview overlay.
  public private(set) var detectedCards: [ScryDetectedCard] = []
  /// The live best guess, refreshed a few times a second while a card is locked.
  public private(set) var previewGuess: PreviewGuess?
  /// Increments every preview cycle — even when the guess is unchanged — so
  /// observers can run per-cycle logic (e.g. bulk stability) that `onChange(of:
  /// previewGuess)` would miss, since that only fires when the value changes.
  public private(set) var previewGeneration = 0

  private var previewTask: Task<Void, Never>?

  public let session = AVCaptureSession()

  private let sessionQueue = DispatchQueue(label: "com.samwagner.Grimora.scry.session")
  private let videoQueue = DispatchQueue(label: "com.samwagner.Grimora.scry.video")
  private let videoOutput = AVCaptureVideoDataOutput()
  private let photoOutput = AVCapturePhotoOutput()
  private var isPhotoOutputConfigured = false
  private let processor: ScryFrameProcessor
  private var isConfigured = false
  private var scanner: ScryScanner?
  private var imageCache: CardImageCache?
  private let symbolPrintCache = ScryFeaturePrintCache()
  /// The rotation the last auto-accepted scan read at — tried first on later
  /// scans and previews, since cards on a rig tend to stay oriented one way.
  private var lastGoodOrientation: CGImagePropertyOrientation?
  private var device: AVCaptureDevice?

  public init(detector: ScryCardDetector = ScryCardDetector()) {
    processor = ScryFrameProcessor(detector: detector)
    processor.onCards = { [weak self] cards in
      Task { @MainActor in self?.detectedCards = cards }
    }
  }

  // MARK: - Lifecycle

  /// Requests permission if needed, configures the session once, and starts it.
  /// The image cache, when provided, lets ambiguous scans be refined by
  /// set-symbol matching against the candidates' cached card images.
  public func start(database: CardDatabase, imageCache: CardImageCache? = nil) async {
    if scanner == nil {
      scanner = ScryScanner(database: database)
    }
    if let imageCache {
      self.imageCache = imageCache
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

  public func stop() {
    detectedCards = []
    previewGuess = nil
    previewTask?.cancel()
    previewTask = nil
    sessionQueue.async { [self] in
      focusSettle?.cancel()
      focusSettle = nil
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
        try? await Task.sleep(for: self.previewCadence())
      }
    }
  }

  /// Adaptive preview cadence: hunt quickly while a card is in view but not yet
  /// confidently read, settle down once the guess is confident, and idle slowly
  /// when nothing card-shaped is in frame.
  private func previewCadence() -> Duration {
    if detectedCards.isEmpty { return .milliseconds(1000) }
    if previewGuess?.confident == true { return .milliseconds(650) }
    return .milliseconds(350)
  }

  private func refreshPreviewGuess() async {
    defer { previewGeneration &+= 1 }
    guard !detectedCards.isEmpty, let scanner else {
      previewGuess = nil
      return
    }
    let processor = self.processor
    let readingOrientation = lastGoodOrientation ?? .up
    previewGuess = await Task.detached(priority: .utility) { () -> PreviewGuess? in
      guard let frame = processor.latestFrame(),
            let resolution = try? scanner.previewScan(
              frame.image,
              orientation: frame.orientation,
              seedCard: frame.cards.first,
              readingOrientation: readingOrientation
            ) else {
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

  /// Runs the full identification pipeline off the main actor. Returns `nil`
  /// when no card could be locked.
  ///
  /// `usingStillCapture` opts into a high-resolution photo capture (tiny
  /// old-frame collector lines need the pixels), falling back to the latest
  /// video frame when the still fails, times out, or sees no card. It is
  /// **only for user-initiated scans**: every capture plays the system shutter
  /// sound, and a passive capture mid-focus-hunt is routinely *blurrier* than
  /// the video frame the preview loop just read — the passive loop learned both
  /// the hard way on device.
  public func scan(usingStillCapture: Bool = false) async -> ScryScanResult? {
    await scanCapturingInput(usingStillCapture: usingStillCapture).result
  }

  /// Like `scan(usingStillCapture:)`, but also hands back the exact image the
  /// pipeline ran on (the high-res still, or the video frame it fell back to) —
  /// for harnesses that archive the scanned input alongside the result.
  public func scanCapturingInput(usingStillCapture: Bool = false) async -> ScryScanCapture {
    guard let scanner else {
      return ScryScanCapture(result: nil, image: nil, orientation: .up, source: .videoFrame)
    }
    let processor = self.processor
    let tryFirst = lastGoodOrientation
    let still = usingStillCapture ? await captureStill(timeout: .seconds(1)) : nil
    let capture = await Task.detached(priority: .userInitiated) { () -> ScryScanCapture in
      if let still,
         let fromStill = try? scanner.scan(still.image, orientation: still.orientation, tryFirst: tryFirst) {
        return ScryScanCapture(
          result: fromStill, image: still.image, orientation: still.orientation, source: .still
        )
      }
      guard let frame = processor.latestFrame() else {
        // No frame to fall back to: surface the still (if any) so a failed scan
        // can still be archived.
        return ScryScanCapture(
          result: nil,
          image: still?.image,
          orientation: still?.orientation ?? .up,
          source: still == nil ? .videoFrame : .still
        )
      }
      let result = try? scanner.scan(frame.image, orientation: frame.orientation, tryFirst: tryFirst)
      return ScryScanCapture(
        result: result, image: frame.image, orientation: frame.orientation, source: .videoFrame
      )
    }.value
    guard let result = capture.result else { return capture }
    if result.resolution.confidence == .auto {
      lastGoodOrientation = result.orientation
    }
    var refined = capture
    refined.result = await refineIfAmbiguous(result)
    return refined
  }

  /// One high-res still, or `nil` past the timeout — a scan must never hang on
  /// the photo pipeline, and the video-frame fallback keeps scans working when
  /// the photo output couldn't be configured at all.
  private func captureStill(
    timeout: Duration
  ) async -> (image: CGImage, orientation: CGImagePropertyOrientation)? {
    guard isPhotoOutputConfigured else { return nil }
    let capture = ScryStillCapture(output: photoOutput, sessionQueue: sessionQueue)
    return await withTaskGroup(of: (CGImage, CGImagePropertyOrientation)?.self) { group in
      group.addTask {
        try? await capture.capture()
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first.map { (image: $0.0, orientation: $0.1) }
    }
  }

  // MARK: - Set-symbol refinement

  /// Above this many candidates a printing picker is faster than fetching a
  /// reference image per candidate.
  private static let maxSymbolRefinementCandidates = 16

  /// Second chance for an ambiguous scan: gather a reference image for each
  /// candidate printing (local cache first, downloading at normal quality when
  /// missing) and let `ScrySymbolMatcher` settle or re-rank the picker by the
  /// set symbol. Offline or with anything missing, the result passes through
  /// untouched — the matcher owns the precision rules.
  private func refineIfAmbiguous(_ result: ScryScanResult) async -> ScryScanResult {
    guard result.resolution.confidence == .ambiguous,
          (2...Self.maxSymbolRefinementCandidates).contains(result.resolution.candidates.count),
          let rectified = result.rectified,
          let imageCache else { return result }

    // Fetch reference images only for candidates whose feature print isn't
    // already cached — a bulk stack of same-name reprints pays for its
    // references once per session.
    let cache = symbolPrintCache
    let needingImages = result.resolution.candidates.filter { candidate in
      guard let band = ScrySymbolBand.referenceBand(for: candidate) else { return false }
      return !cache.hasObservation(for: candidate.id, band: band)
    }
    let references = await Self.referenceImages(for: needingImages, imageCache: imageCache)

    let resolution = result.resolution
    let orientation = result.orientation
    let lineMap = result.lineMap
    let refined = await Task.detached(priority: .userInitiated) {
      ScrySymbolMatcher().refine(
        resolution,
        scan: rectified,
        orientation: orientation,
        lineMap: lineMap,
        referenceImages: references,
        referenceCache: cache
      )
    }.value

    var updated = result
    updated.resolution = refined
    return updated
  }

  private static func referenceImages(
    for candidates: [CardRecord],
    imageCache: CardImageCache
  ) async -> [String: CGImage] {
    await withTaskGroup(of: (String, CGImage)?.self) { group in
      for candidate in candidates {
        group.addTask {
          guard let image = await referenceImage(for: candidate, imageCache: imageCache) else {
            return nil
          }
          return (candidate.id, image)
        }
      }
      var references: [String: CGImage] = [:]
      for await pair in group {
        if let (id, image) = pair {
          references[id] = image
        }
      }
      return references
    }
  }

  private static func referenceImage(
    for card: CardRecord,
    imageCache: CardImageCache
  ) async -> CGImage? {
    if let image = loadImage(atPath: card.displayImagePath) {
      return image
    }
    guard let updated = try? await imageCache.cacheDisplayedImageRecord(for: card, quality: .normal) else {
      return nil
    }
    return loadImage(atPath: updated.displayImagePath)
  }

  private static func loadImage(atPath path: String?) -> CGImage? {
    guard let path, !path.isEmpty else { return nil }
    let url: URL = if let parsed = URL(string: path), parsed.isFileURL {
      parsed
    } else {
      URL(fileURLWithPath: path)
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
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

    // High-resolution stills feed the full identification scan: the 1080p video
    // feed is fine for detection/preview but starves OCR of pixels whenever the
    // card doesn't fill the frame (the old-frame collector line dies first).
    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
      if let maxDimensions = device?.activeFormat.supportedMaxPhotoDimensions.last {
        photoOutput.maxPhotoDimensions = maxDimensions
      }
      photoOutput.maxPhotoQualityPrioritization = .balanced
      if photoOutput.isZeroShutterLagSupported {
        photoOutput.isZeroShutterLagEnabled = true
      }
      if photoOutput.isResponsiveCaptureSupported {
        photoOutput.isResponsiveCaptureEnabled = true
      }
      isPhotoOutputConfigured = true
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
      // Full range, not `.near`: on a lightbox rig the card can sit past the
      // near band, where a `.near` restriction stops AF from ever converging.
      // The center-weighted `focusPointOfInterest` still keeps it off the walls.
      device.autoFocusRangeRestriction = .none
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

  /// The in-flight tap/refocus settle, so a newer request can supersede it.
  private var focusSettle: ScryFocusSettleCoordinator?

  /// Locks or unlocks focus and exposure at the current setting. Retained for the
  /// single-mode entry path; the bulk rig now prefers `beginBulkFocus` (centered
  /// continuous AF) over a hard lock that could freeze on a soft frame.
  public func setFocusLocked(_ locked: Bool) {
    sessionQueue.async { [self] in
      focusSettle?.cancel()
      focusSettle = nil
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

  /// Bulk-mode steady state: center-weighted continuous autofocus, no lock. A
  /// fixed rig re-converges per placement on its own — and, unlike locking on
  /// entry, it never freezes on the (often empty-box) first frame and leaves
  /// every later card soft.
  public func beginBulkFocus() {
    sessionQueue.async { [self] in
      focusSettle?.cancel()
      focusSettle = nil
      applyCenteredContinuousFocus()
    }
  }

  /// Tap-to-focus: one-shot AF + AE at a point in the camera's device coordinate
  /// space (origin top-left, normalized), then — once the lens *actually* stops
  /// hunting (observed via `ScryFocusSettleCoordinator`, not a fixed timer) —
  /// hand back to continuous AF so the next card re-converges. Waiting for the
  /// real settle is what keeps a tap from freezing a mid-hunt, soft frame.
  public func focus(atDevicePoint point: CGPoint) {
    sessionQueue.async { [self] in
      applyOneShotFocus(at: point)
      beginFocusSettle()
    }
  }

  /// Refocus button / rig repositioned: one-shot on center, then continuous.
  public func refocusCenter() {
    focus(atDevicePoint: CGPoint(x: 0.5, y: 0.5))
  }

  // MARK: - Focus helpers (all run on `sessionQueue`)

  private func applyOneShotFocus(at point: CGPoint) {
    focusSettle?.cancel()
    focusSettle = nil
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

  private func beginFocusSettle() {
    guard let device else { return }
    let coordinator = ScryFocusSettleCoordinator(device: device, sessionQueue: sessionQueue) { [weak self] in
      // Fires on `sessionQueue` (the coordinator's completion).
      self?.resumeContinuousFocusAfterSettle()
    }
    focusSettle = coordinator
    coordinator.begin()
  }

  private func resumeContinuousFocusAfterSettle() {
    applyCenteredContinuousFocus()
    focusSettle = nil
  }

  private func applyCenteredContinuousFocus() {
    guard let device, (try? device.lockForConfiguration()) != nil else { return }
    let center = CGPoint(x: 0.5, y: 0.5)
    if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    device.unlockForConfiguration()
  }
}
#endif
