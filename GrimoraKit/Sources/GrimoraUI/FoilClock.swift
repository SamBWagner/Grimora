import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A single shared, slowly-advancing clock that drives the self-animating foil sheen (grids +
/// detail). Every on-screen foil overlay reads this one ref-counted source rather than spinning
/// up its own `TimelineView`, so N foil tiles cost one animation stream. The clock only runs
/// while at least one overlay is visible.
///
/// `time` accumulates elapsed seconds (starting at zero) so it stays small enough to keep full
/// precision when narrowed to `Float` for the Metal `time` uniform.
///
/// On iOS/visionOS it's driven by a **`CADisplayLink`**: vsync-aligned callbacks that accumulate
/// the *real* frame delta, so the animation flows smoothly and stays time-correct even if a frame
/// is dropped (a plain `Timer` in `.default` mode gets starved by main-thread work and lurches —
/// the "frozen then jumps" stutter, worst for the heavier shaders like fracture). macOS keeps a
/// simple timer. Capped at 60fps to bound redraw load on 120Hz displays.
@MainActor
final class FoilClock: ObservableObject {
    static let shared = FoilClock()

    /// Accumulated seconds since the clock started ticking.
    @Published private(set) var time: Double = 0

    private var subscribers = 0

    private init() {}

    #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    private let proxy = FoilDisplayLinkProxy()
    private var lastTimestamp: CFTimeInterval = 0

    func subscribe() {
        subscribers += 1
        guard subscribers == 1, displayLink == nil else { return }
        lastTimestamp = 0
        proxy.onTick = { [weak self] link in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.lastTimestamp == 0 {
                    self.lastTimestamp = link.timestamp
                    return
                }
                let delta = link.timestamp - self.lastTimestamp
                self.lastTimestamp = link.timestamp
                // Clamp so a stall (backgrounding, GPU hitch) advances by at most one slow frame
                // rather than lurching forward by the whole gap.
                self.time += min(max(delta, 0), 1.0 / 15.0)
            }
        }
        let link = CADisplayLink(target: proxy, selector: #selector(FoilDisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }
    #else
    private var timer: Timer?
    private static let tickInterval: Double = 1.0 / 60.0

    func subscribe() {
        subscribers += 1
        guard subscribers == 1, timer == nil else { return }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.time += Self.tickInterval }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
    #endif
}

#if canImport(UIKit)
/// Bridges the `CADisplayLink` `@objc` callback back to the `FoilClock`. The link retains this
/// proxy; the proxy holds `FoilClock` weakly (via the closure), so there's no retain cycle.
private final class FoilDisplayLinkProxy: NSObject {
    var onTick: (CADisplayLink) -> Void = { _ in }

    @objc func tick(_ link: CADisplayLink) {
        onTick(link)
    }
}
#endif
