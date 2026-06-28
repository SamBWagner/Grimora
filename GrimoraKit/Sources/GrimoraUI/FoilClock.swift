import Foundation

/// A single shared, slowly-advancing clock that drives the self-animating grid foil sheen.
///
/// On macOS (and visionOS) there is no device motion to move the foil, so the shimmer has to
/// animate on its own. Rather than give every foil tile its own `TimelineView` — which would
/// spin up N independent ~60fps invalidation streams — every on-screen grid foil overlay
/// reads this one ref-counted source, mirroring the `FoilMotionCenter` pattern used for the
/// iOS gyro stream. The timer only runs while at least one grid foil overlay is visible.
///
/// `time` accumulates elapsed seconds (starting at zero) rather than wall-clock, so it stays
/// small enough to keep full precision when narrowed to `Float` for the Metal `time` uniform.
///
/// The timer is scheduled in the default run-loop mode, so on iOS it naturally pauses while a
/// scroll view is tracking a drag and resumes when the grid settles — the shimmer animates at
/// rest and costs nothing mid-fling, which is exactly what we want for scroll smoothness.
@MainActor
final class FoilClock: ObservableObject {
    static let shared = FoilClock()

    /// Accumulated seconds since the clock started ticking.
    @Published private(set) var time: Double = 0

    /// ~24fps — plenty for a slow holographic drift, and a fraction of the work of 60.
    private static let tickInterval: Double = 1.0 / 24.0

    private var timer: Timer?
    private var subscribers = 0

    private init() {}

    func subscribe() {
        subscribers += 1
        guard subscribers == 1, timer == nil else { return }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.time += Self.tickInterval
            }
        }
        // Default mode pauses during iOS scroll tracking (intentional); .default is implied
        // by scheduledTimer but we add it explicitly so the intent is documented.
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}
