#if os(iOS)
import AVFoundation
import Foundation
import GrimoraCore

/// Bridges `AVCaptureDevice.isAdjustingFocus` KVO to the pure `ScryFocusSettle`
/// state machine, so a one-shot autofocus is finalized (handed back to
/// continuous AF) only after the lens actually stops hunting — never on a fixed
/// timer that can freeze a mid-hunt, soft frame.
///
/// One instance per focus request. The owner (`ScryCameraController`) holds it
/// for the request's lifetime and calls `cancel()` to supersede it when a newer
/// tap arrives; it invalidates its observation on settle, cancel, or dealloc.
///
/// All device access happens on the owner's `sessionQueue`. KVO callbacks fire
/// on an AVFoundation-internal queue, so every sample hops back onto
/// `sessionQueue` before touching state — matching where the controller applies
/// its `lockForConfiguration` changes.
final class ScryFocusSettleCoordinator: @unchecked Sendable {
  private weak var device: AVCaptureDevice?
  private let sessionQueue: DispatchQueue
  private var settle: ScryFocusSettle
  private var observation: NSKeyValueObservation?
  private let start = ContinuousClock.now
  private var finished = false
  private let onSettled: () -> Void

  init(
    device: AVCaptureDevice,
    sessionQueue: DispatchQueue,
    settle: ScryFocusSettle = ScryFocusSettle(),
    onSettled: @escaping () -> Void
  ) {
    self.device = device
    self.sessionQueue = sessionQueue
    self.settle = settle
    self.onSettled = onSettled
  }

  deinit { observation?.invalidate() }

  /// Starts observing. Must be called on `sessionQueue`, right after the
  /// one-shot focus was applied to the device.
  func begin() {
    guard let device else { return finish() }
    observation = device.observe(\.isAdjustingFocus, options: [.initial, .new]) { [weak self] device, _ in
      self?.sample(isAdjusting: device.isAdjustingFocus)
    }
    // The KVO stream only delivers *changes*, so an already-sharp lens that never
    // hunts would otherwise wait out the whole timeout. A tick just past the
    // grace window resolves that case; a tick at the deadline guarantees
    // termination even if the lens is stuck hunting.
    sessionQueue.asyncAfter(deadline: .now() + settle.grace.seconds) { [weak self] in
      self?.sample(isAdjusting: self?.device?.isAdjustingFocus ?? false)
    }
    sessionQueue.asyncAfter(deadline: .now() + settle.timeout.seconds) { [weak self] in
      self?.sample(isAdjusting: self?.device?.isAdjustingFocus ?? false)
    }
  }

  /// Supersede / tear down without firing the completion.
  func cancel() {
    sessionQueue.async { [weak self] in
      guard let self, !self.finished else { return }
      self.finished = true
      self.observation?.invalidate()
      self.observation = nil
    }
  }

  private func sample(isAdjusting: Bool) {
    sessionQueue.async { [weak self] in
      guard let self, !self.finished else { return }
      let elapsed = self.start.duration(to: .now)
      let decision = self.settle.update(isAdjusting: isAdjusting, elapsed: elapsed)
      guard decision != .waiting else { return }
      self.finished = true
      self.observation?.invalidate()
      self.observation = nil
      self.onSettled()
    }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    observation?.invalidate()
    observation = nil
    onSettled()
  }
}

private extension Duration {
  /// Seconds as a `TimeInterval`, for scheduling on a `DispatchQueue`.
  var seconds: Double {
    let c = components
    return Double(c.seconds) + Double(c.attoseconds) * 1e-18
  }
}
#endif
