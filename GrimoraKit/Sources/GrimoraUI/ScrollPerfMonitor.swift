import Foundation
import OSLog
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Shared plumbing for Grimora's scroll-performance instrumentation.
///
/// The intervals and events emitted through `signposter` show up in Instruments' os_signpost /
/// Points-of-Interest track, so a Time Profiler / Hitches trace can attribute a dropped frame to
/// the work that caused it (image decode, section rebuild, …). The hitch monitor below also mirrors
/// a plain-text summary to the unified log so slowdowns can be watched live from a terminal:
///
///     xcrun simctl spawn booted log stream --predicate 'subsystem == "com.grimora.perf"'
///
/// Everything here is opt-in — nothing starts unless `GRIMORA_PERF_HUD=1` is set — so it adds no
/// cost to a normal run.
enum GrimoraPerf {
  static let subsystem = "com.grimora.perf"
  static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
  static let log = Logger(subsystem: subsystem, category: "scroll")

  /// Whether the on-screen frame-rate HUD (and the CADisplayLink hitch monitor behind it) should
  /// run. Off by default; flip on with the `GRIMORA_PERF_HUD=1` launch environment variable.
  static let isHUDEnabled = ProcessInfo.processInfo.environment["GRIMORA_PERF_HUD"] == "1"

  /// Escape hatch to A/B the off-main image predecode against the old draw-time decode without a
  /// rebuild. Set `GRIMORA_DISABLE_IMAGE_PREDECODE=1` to reproduce the pre-fix behaviour.
  static let isImagePredecodeDisabled =
    ProcessInfo.processInfo.environment["GRIMORA_DISABLE_IMAGE_PREDECODE"] == "1"
}

/// A `CADisplayLink`-driven frame-time monitor. It watches the real vsync cadence and, over a short
/// rolling window, reports the achieved frame rate, how many frames were long enough to read as a
/// visible stutter ("hitches"), and the single worst frame. A hitch is a frame whose wall-clock
/// duration ran past 1.5× the display's nominal frame interval — i.e. the render loop missed its
/// slot, which is exactly what "choppy scrolling" feels like.
///
/// Only the per-window summary mutates the observable properties (≈ twice a second), so driving the
/// HUD never itself invalidates the card grid on every frame.
@MainActor
@Observable
final class ScrollHitchMonitor {
  static let shared = ScrollHitchMonitor()

  /// Achieved frames per second over the most recent window.
  private(set) var framesPerSecond: Double = 0
  /// Number of hitched frames in the most recent window.
  private(set) var hitchesInWindow: Int = 0
  /// Duration of the single worst frame in the most recent window, in milliseconds.
  private(set) var worstFrameMilliseconds: Double = 0
  /// Running total of hitches since the monitor started — a cheap "how bad was that scroll" tally.
  private(set) var totalHitches: Int = 0
  /// Cumulative milliseconds of frame time spent *over* the display's per-frame budget since the
  /// monitor started. Unlike the thresholded hitch count (which saturates when every frame is slow),
  /// this is a monotonic magnitude — the total wall-clock the render loop fell behind — so it can
  /// still discriminate a smaller vs larger main-thread cost even during sustained jank.
  private(set) var cumulativeJankMilliseconds: Double = 0
  private(set) var isRunning = false

  /// Machine-readable one-liner mirrored onto the HUD's accessibility value so a UI test can read
  /// the live counters back (`total=` hitch tally, `jank=` cumulative over-budget ms — both used by
  /// the scroll benchmark).
  var statusValue: String {
    "total=\(totalHitches) jank=\(Int(cumulativeJankMilliseconds.rounded())) worst=\(Int(worstFrameMilliseconds.rounded())) fps=\(Int(framesPerSecond.rounded()))"
  }

  private static let windowSeconds: Double = 0.5

  private var windowFrames = 0
  private var windowElapsed: Double = 0
  private var windowHitches = 0
  private var windowWorstSeconds: Double = 0

  private init() {}

  #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    private let proxy = HitchDisplayLinkProxy()
    private var lastTimestamp: CFTimeInterval = 0

    func start() {
      guard displayLink == nil else { return }
      resetWindow()
      lastTimestamp = 0
      proxy.onTick = { [weak self] link in
        MainActor.assumeIsolated {
          self?.tick(link)
        }
      }
      let link = CADisplayLink(target: proxy, selector: #selector(HitchDisplayLinkProxy.tick(_:)))
      // Track the display's real ceiling (up to 120Hz) so a hitch is measured against the cadence
      // the app is actually trying to hit, not a fixed 60.
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      displayLink = link
      isRunning = true
    }

    func stop() {
      displayLink?.invalidate()
      displayLink = nil
      lastTimestamp = 0
      isRunning = false
    }

    private func tick(_ link: CADisplayLink) {
      let now = link.timestamp
      defer { lastTimestamp = now }
      guard lastTimestamp > 0 else { return }

      let frameDuration = now - lastTimestamp
      // The display link's own advertised interval to the next frame is the nominal budget for this
      // device/refresh rate; fall back to 60Hz if it isn't reported yet.
      let nominal = link.targetTimestamp > link.timestamp
        ? link.targetTimestamp - link.timestamp
        : 1.0 / 60.0
      let hitchThreshold = nominal * 1.5

      cumulativeJankMilliseconds += max(0, frameDuration - nominal) * 1000
      windowFrames += 1
      windowElapsed += frameDuration

      if frameDuration > hitchThreshold {
        windowHitches += 1
        totalHitches += 1
        windowWorstSeconds = max(windowWorstSeconds, frameDuration)
        GrimoraPerf.signposter.emitEvent("hitch")
        // Only shout about big stalls individually; the per-window summary covers the rest.
        if frameDuration > nominal * 3 {
          GrimoraPerf.log.error(
            "hitch \(frameDuration * 1000, format: .fixed(precision: 1))ms (budget \(nominal * 1000, format: .fixed(precision: 1))ms)"
          )
        }
      }

      guard windowElapsed >= Self.windowSeconds else { return }

      framesPerSecond = Double(windowFrames) / windowElapsed
      hitchesInWindow = windowHitches
      worstFrameMilliseconds = windowWorstSeconds * 1000
      if windowHitches > 0 {
        GrimoraPerf.log.log(
          "fps \(self.framesPerSecond, format: .fixed(precision: 0)) hitches \(self.windowHitches) worst \(self.worstFrameMilliseconds, format: .fixed(precision: 1))ms"
        )
      }
      resetWindow()
    }
  #else
    func start() {}
    func stop() {}
    private func tick() {}
  #endif

  private func resetWindow() {
    windowFrames = 0
    windowElapsed = 0
    windowHitches = 0
    windowWorstSeconds = 0
  }
}

#if canImport(UIKit)
  /// Bridges the `CADisplayLink` `@objc` callback back to the monitor. The link retains this proxy;
  /// the proxy holds the monitor weakly via the closure, so there's no retain cycle. Mirrors the
  /// proven `FoilClock` display-link pattern.
  private final class HitchDisplayLinkProxy: NSObject {
    var onTick: (CADisplayLink) -> Void = { _ in }

    @objc func tick(_ link: CADisplayLink) {
      onTick(link)
    }
  }
#endif

/// A compact heads-up display showing the live frame rate, hitch count, and worst frame. Green when
/// scrolling is smooth, amber/red as frames start dropping — so a slowdown is visible the instant it
/// happens without a tethered Instruments session.
struct PerfHUDView: View {
  @State private var monitor = ScrollHitchMonitor.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(Int(monitor.framesPerSecond.rounded())) fps")
        .foregroundStyle(fpsColor)
      Text("hitch \(monitor.hitchesInWindow) · \(monitor.worstFrameMilliseconds, format: .number.precision(.fractionLength(0)))ms")
        .foregroundStyle(monitor.hitchesInWindow > 0 ? Color.orange : Color.green)
      Text("Σ \(monitor.totalHitches)")
        .foregroundStyle(.secondary)
    }
    .font(.system(size: 11, weight: .semibold, design: .monospaced))
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .foregroundStyle(.white)
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("perf-hud-status")
    .accessibilityValue(monitor.statusValue)
    .task {
      monitor.start()
    }
    .onDisappear {
      monitor.stop()
    }
  }

  private var fpsColor: Color {
    switch monitor.framesPerSecond {
    case ..<45: return .red
    case ..<75: return .orange
    default: return .green
    }
  }
}

extension View {
  /// Overlays the frame-rate HUD when `GRIMORA_PERF_HUD=1` is set; otherwise returns `self`
  /// untouched, so the instrumentation is entirely absent from a normal run.
  @ViewBuilder
  func grimoraPerfHUD() -> some View {
    #if canImport(UIKit)
      if GrimoraPerf.isHUDEnabled {
        overlay(alignment: .topTrailing) {
          PerfHUDView()
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
      } else {
        self
      }
    #else
      self
    #endif
  }
}
