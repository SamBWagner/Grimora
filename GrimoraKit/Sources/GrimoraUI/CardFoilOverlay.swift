import GrimoraCore
import SwiftUI
#if os(iOS)
import CoreMotion
#endif

// MARK: - Foil shimmer (Metal)

/// A synthetic holographic foil sheen drawn over card artwork — used in both grid thumbnails
/// (search / collections) and the detail pane. Scryfall does not host foil versions of card
/// art, so foil is rendered here rather than fetched. A GPU shader (`Foil.metal`) does the
/// per-pixel holographic work, so a whole grid of foil cards can animate without loading the
/// main thread.
///
/// The treatment is tiered:
/// - **iOS:** the hue + specular highlight track device tilt (Core Motion), so the card
///   "catches the light" as you move the phone — offset per card so a grid never shimmers in
///   lockstep, and a stationary phone rests at a per-card-unique sheen.
/// - **macOS / visionOS:** a self-animating sweep from the shared `FoilClock` (no device to
///   tilt), each card advancing at its own seeded rate and offset.
/// - **Reduce Motion (any platform):** a static — but still per-card-seeded — sheen.
///
/// `intensity` scales the sheen: the detail pane renders full strength (1.0); grids stay
/// restrained so a dense wall of foils reads as tasteful rather than noisy. `FoilSeed` gives
/// every card a unique phase / speed / angle so neighbours never pulse in unison.
struct CardFoilShimmerOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The resting phase used for static treatments, chosen so the specular band sits across
    /// the card rather than tucked into a corner.
    static let restingPhase = 0.35

    /// Self-animation rate (hue cycles per second, before the per-card speed multiplier) for
    /// the looping drift on macOS / visionOS, where there's no device to tilt. iOS is gyro-only
    /// and doesn't use this.
    static let driftRate: Double = 0.15

    var cornerRadius: CGFloat = 8
    var seed: FoilSeed
    /// Sheen strength. 1.0 is the full detail-pane look; grids pass a restrained value.
    var intensity: Double = 1.0

    var body: some View {
        if reduceMotion {
            ShaderFoilSheen(
                phase: Self.restingPhase + seed.phaseOffset,
                seed: seed,
                intensity: intensity,
                cornerRadius: cornerRadius
            )
        } else {
            #if os(iOS)
            MotionShaderFoilSheen(seed: seed, intensity: intensity, cornerRadius: cornerRadius)
            #else
            ClockShaderFoilSheen(seed: seed, intensity: intensity, cornerRadius: cornerRadius)
            #endif
        }
    }
}

/// The stateless shader visual. `phase` advances the holographic wash + specular band; the
/// black base contributes nothing under `.plusLighter`, so only the sheen brightens the art.
private struct ShaderFoilSheen: View {
    var phase: Double
    var seed: FoilSeed
    var intensity: Double
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { proxy in
            Rectangle()
                .fill(.black)
                .colorEffect(
                    ShaderLibrary.bundle(.module).grimoraFoil(
                        .float2(proxy.size),
                        .float(Float(phase)),
                        .float(Float(seed.angle)),
                        .float(Float(intensity))
                    )
                )
        }
        .blendMode(.plusLighter)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
    }
}

#if os(iOS)
/// iOS foil: driven purely by the device gyro/accelerometer (shared stream), offset and scaled
/// per card so a grid never shimmers in lockstep. There's no self-animating drift here — on a
/// handheld device, moving the device *is* the animation, which reads cleaner than a loop.
private struct MotionShaderFoilSheen: View {
    @ObservedObject private var motion = FoilMotionCenter.shared

    var seed: FoilSeed
    var intensity: Double
    var cornerRadius: CGFloat

    var body: some View {
        ShaderFoilSheen(
            phase: motion.phase * seed.speed + seed.phaseOffset,
            seed: seed,
            intensity: intensity,
            cornerRadius: cornerRadius
        )
        .onAppear { motion.subscribe() }
        .onDisappear { motion.unsubscribe() }
    }
}

/// A single shared Core Motion source so any number of on-screen foil cards read one
/// device-motion stream. Ref-counted: the gyroscope only runs while at least one foil overlay
/// is visible.
@MainActor
private final class FoilMotionCenter: ObservableObject {
    static let shared = FoilMotionCenter()

    @Published private(set) var phase: Double = CardFoilShimmerOverlay.restingPhase

    private let manager = CMMotionManager()
    private var subscribers = 0

    func subscribe() {
        subscribers += 1
        guard subscribers == 1,
              manager.isDeviceMotionAvailable,
              !manager.isDeviceMotionActive
        else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let combined = (motion.attitude.roll + motion.attitude.pitch) / (2 * .pi)
            let newPhase = combined - floor(combined)
            MainActor.assumeIsolated {
                self?.phase = newPhase
            }
        }
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        manager.stopDeviceMotionUpdates()
        phase = CardFoilShimmerOverlay.restingPhase
    }
}
#else
/// macOS / visionOS foil: self-animates from the shared clock, each card advancing at its own
/// seeded rate and offset.
private struct ClockShaderFoilSheen: View {
    @ObservedObject private var clock = FoilClock.shared

    var seed: FoilSeed
    var intensity: Double
    var cornerRadius: CGFloat

    var body: some View {
        ShaderFoilSheen(
            phase: clock.time * CardFoilShimmerOverlay.driftRate * seed.speed + seed.phaseOffset,
            seed: seed,
            intensity: intensity,
            cornerRadius: cornerRadius
        )
        .onAppear { clock.subscribe() }
        .onDisappear { clock.unsubscribe() }
    }
}
#endif
