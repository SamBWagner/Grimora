import Foundation
import OSLog
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif os(macOS)
  import AppKit
  import QuartzCore
#endif

/// Shared plumbing for Grimora's scroll-performance instrumentation.
///
/// The intervals and events emitted through `signposter` show up in Instruments' os_signpost /
/// Points-of-Interest track, so a Time Profiler / Hitches trace can attribute a dropped frame to
/// the work that caused it (image decode, section rebuild, …). The hitch monitor below also mirrors
/// a plain-text summary to the unified log so slowdowns can be watched live from a terminal:
///
///     # iOS simulator:
///     xcrun simctl spawn booted log stream --predicate 'subsystem == "com.grimora.perf"'
///     # macOS app:
///     log stream --predicate 'subsystem == "com.grimora.perf"'
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

/// Plain (non-`@Observable`) main-thread tallies bumped from instrumented hot paths to attribute
/// scroll jank: how often the grid re-packs its rows, how many tile bodies evaluate, and how often
/// the list-detail snapshot rebuilds. They live outside the observation graph so a bump never
/// invalidates a view (which would perturb the very thing we're measuring); `ScrollHitchMonitor`
/// samples a snapshot on its ~2Hz window tick and publishes *that* for the HUD/benchmark to read.
/// Every bump is a no-op unless the HUD is enabled, so normal runs pay nothing.
@MainActor
final class PerfCounters {
  static let shared = PerfCounters()

  var gridRowPacks = 0
  var tileBodyEvals = 0
  var snapshotBuilds = 0

  private init() {}

  static func bumpGridRowPacks() {
    guard GrimoraPerf.isHUDEnabled else { return }
    shared.gridRowPacks += 1
  }

  static func bumpTileBodyEvals() {
    guard GrimoraPerf.isHUDEnabled else { return }
    shared.tileBodyEvals += 1
  }

  static func bumpSnapshotBuilds() {
    guard GrimoraPerf.isHUDEnabled else { return }
    shared.snapshotBuilds += 1
  }
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
  /// Snapshots of the `PerfCounters` tallies, refreshed each window tick so the HUD/benchmark can
  /// read them without the counters driving re-renders.
  private(set) var gridRowPacks = 0
  private(set) var tileBodyEvals = 0
  private(set) var snapshotBuilds = 0
  private(set) var isRunning = false

  /// Machine-readable one-liner mirrored onto the HUD's accessibility value so a UI test can read
  /// the live counters back (`total=` hitch tally, `jank=` cumulative over-budget ms — both used by
  /// the scroll benchmark).
  var statusValue: String {
    "total=\(totalHitches) jank=\(Int(cumulativeJankMilliseconds.rounded())) packs=\(gridRowPacks) tiles=\(tileBodyEvals) snaps=\(snapshotBuilds) worst=\(Int(worstFrameMilliseconds.rounded())) fps=\(Int(framesPerSecond.rounded()))"
  }

  private static let windowSeconds: Double = 0.5

  private var windowFrames = 0
  private var windowElapsed: Double = 0
  private var windowHitches = 0
  private var windowWorstSeconds: Double = 0

  private init() {}

  private var lastTimestamp: CFTimeInterval = 0

  /// Records one frame's timing. Fed by the platform display-link source — a self-owned
  /// `CADisplayLink` on iOS/visionOS, an `NSView`-vended one on macOS — so the hitch/jank/counter
  /// math is byte-identical across platforms.
  func recordFrame(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {
    let now = timestamp
    defer { lastTimestamp = now }
    guard lastTimestamp > 0 else { return }

    let frameDuration = now - lastTimestamp
    // The display link's own advertised interval to the next frame is the nominal budget for this
    // device/refresh rate; fall back to 60Hz if it isn't reported yet.
    let nominal = targetTimestamp > timestamp ? targetTimestamp - timestamp : 1.0 / 60.0
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
    let counters = PerfCounters.shared
    gridRowPacks = counters.gridRowPacks
    tileBodyEvals = counters.tileBodyEvals
    snapshotBuilds = counters.snapshotBuilds
    if windowHitches > 0 {
      GrimoraPerf.log.log(
        "fps \(self.framesPerSecond, format: .fixed(precision: 0)) hitches \(self.windowHitches) worst \(self.worstFrameMilliseconds, format: .fixed(precision: 1))ms"
      )
    }
    resetWindow()
  }

  private func beginRun() {
    resetWindow()
    lastTimestamp = 0
    isRunning = true
  }

  private func endRun() {
    lastTimestamp = 0
    isRunning = false
  }

  #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    private let proxy = HitchDisplayLinkProxy()

    func start() {
      guard displayLink == nil else { return }
      beginRun()
      proxy.onTick = { [weak self] link in
        MainActor.assumeIsolated {
          self?.recordFrame(timestamp: link.timestamp, targetTimestamp: link.targetTimestamp)
        }
      }
      let link = CADisplayLink(target: proxy, selector: #selector(HitchDisplayLinkProxy.tick(_:)))
      // Track the display's real ceiling (up to 120Hz) so a hitch is measured against the cadence
      // the app is actually trying to hit, not a fixed 60.
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      displayLink = link
    }

    func stop() {
      displayLink?.invalidate()
      displayLink = nil
      endRun()
    }
  #elseif os(macOS)
    // macOS has no standalone CADisplayLink — it must be vended by a view — so the invisible
    // `MacFrameTicker` embedded in the HUD owns the link and feeds `recordFrame`. start()/stop()
    // just bracket a measurement run (reset counters, flip `isRunning`).
    func start() {
      guard !isRunning else { return }
      beginRun()
    }

    func stop() {
      endRun()
    }
  #else
    func start() {}
    func stop() {}
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
    .background { frameTicker }
    .foregroundStyle(.white)
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("perf-hud-status")
    // Publish the status as BOTH value and label: iOS XCUITest reads it as `.value`, but macOS
    // doesn't surface `AXValue` on a non-control element, so the Mac benchmark reads `.label`.
    .accessibilityValue(monitor.statusValue)
    .accessibilityLabel(monitor.statusValue)
    .task {
      monitor.start()
    }
    .onDisappear {
      monitor.stop()
    }
  }

  /// On macOS the display link has to be vended by a view, so the HUD hosts an invisible ticker that
  /// drives the shared monitor. iOS/visionOS drive the monitor's own `CADisplayLink`, so no ticker.
  @ViewBuilder
  private var frameTicker: some View {
    #if os(macOS)
      MacFrameTicker().allowsHitTesting(false)
    #else
      Color.clear
    #endif
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
    if GrimoraPerf.isHUDEnabled {
      overlay(alignment: .topTrailing) {
        PerfHUDView()
          .padding(.top, 8)
          .padding(.trailing, 8)
      }
    } else {
      self
    }
  }
}

#if os(macOS)
  /// Bridges an `NSView`-vended `CADisplayLink` (macOS 14+) into the shared `ScrollHitchMonitor`, so
  /// the Mac gets the same vsync-aligned frame callbacks as the iOS path. The link is created once the
  /// view is in a window (it needs the window's screen) and torn down when the view leaves or the
  /// representable is dismantled.
  private struct MacFrameTicker: NSViewRepresentable {
    func makeNSView(context: Context) -> MacFrameTickerView {
      MacFrameTickerView()
    }

    func updateNSView(_ nsView: MacFrameTickerView, context: Context) {}

    static func dismantleNSView(_ nsView: MacFrameTickerView, coordinator: Coordinator) {
      nsView.stopFrameLink()
    }
  }

  final class MacFrameTickerView: NSView {
    private var frameLink: CADisplayLink?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil {
        stopFrameLink()
      } else {
        startFrameLink()
      }
    }

    private func startFrameLink() {
      guard frameLink == nil else { return }
      let link = displayLink(target: self, selector: #selector(frameTick(_:)))
      // Track the display's real ceiling (ProMotion up to 120Hz) so a hitch is measured against the
      // cadence the app is trying to hit. `.common` keeps the link firing during scroll tracking.
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      frameLink = link
    }

    func stopFrameLink() {
      frameLink?.invalidate()
      frameLink = nil
    }

    @objc private func frameTick(_ link: CADisplayLink) {
      MainActor.assumeIsolated {
        ScrollHitchMonitor.shared.recordFrame(
          timestamp: link.timestamp, targetTimestamp: link.targetTimestamp)
      }
    }
  }
#endif
