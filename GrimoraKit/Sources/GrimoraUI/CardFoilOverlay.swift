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

    /// Base rate at which the shared-clock `phase` advances, per second, before the per-card
    /// speed multiplier. The per-treatment shaders were tuned in real-time canvas prototypes, so
    /// this is ~1.0 to make one unit of `phase` ≈ one second — much lower (the old 0.15, sized for
    /// the original ultra-subtle standard shimmer) reads as "incredibly slow" for the new effects.
    /// Drives the self-animating drift on all platforms; iOS layers device-tilt phase on top.
    static let driftRate: Double = 1.0

    var cornerRadius: CGFloat = 8
    var seed: FoilSeed
    /// Which foil treatment to render. Selects the GPU shader (plain foil, etched, or a special
    /// promo treatment); the motion/clock/static tiering below is identical for all of them.
    var treatment: CardFoilTreatment = .standard
    /// Sheen strength. 1.0 is the full detail-pane look; grids pass a restrained value.
    var intensity: Double = 1.0

    var body: some View {
        if treatment == .invisibleInk {
            // Invisible ink is a hidden foil scrawl, not a rainbow sheen — render only its layer.
            InvisibleInkOverlay(cornerRadius: cornerRadius, intensity: intensity)
        } else {
            ZStack {
                sheen
                // Mana foil is the one treatment whose identity is the stamped symbols themselves —
                // drawn as a SwiftUI layer (the app's SF Symbol mana glyphs) over the gradient sheen.
                if treatment == .mana {
                    ManaFoilStampOverlay(cornerRadius: cornerRadius, intensity: intensity)
                }
            }
        }
    }

    @ViewBuilder
    private var sheen: some View {
        if reduceMotion {
            ShaderFoilSheen(
                phase: Self.restingPhase + seed.phaseOffset,
                seed: seed,
                treatment: treatment,
                intensity: intensity,
                cornerRadius: cornerRadius
            )
        } else {
            #if os(iOS)
            MotionShaderFoilSheen(seed: seed, treatment: treatment, intensity: intensity, cornerRadius: cornerRadius)
            #else
            ClockShaderFoilSheen(seed: seed, treatment: treatment, intensity: intensity, cornerRadius: cornerRadius)
            #endif
        }
    }
}

/// The stateless shader visual. `phase` advances the holographic wash + specular band; the
/// black base contributes nothing under `.plusLighter`, so only the sheen brightens the art.
private struct ShaderFoilSheen: View {
    var phase: Double
    var seed: FoilSeed
    var treatment: CardFoilTreatment
    var intensity: Double
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { proxy in
            Rectangle()
                .fill(.black)
                .colorEffect(foilShader(size: proxy.size))
        }
        .blendMode(.plusLighter)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    private func foilShader(size: CGSize) -> Shader {
        let function = ShaderFunction(library: .bundle(.module), name: Self.shaderName(for: treatment))
        return Shader(function: function, arguments: [
            .float2(size),
            .float(Float(phase)),
            .float(Float(seed.angle)),
            .float(Float(intensity))
        ])
    }

    /// The single dispatch point from treatment → Metal function. Treatments without a bespoke
    /// shader yet fall back to the plain `grimoraFoil` sheen; a follow-up adds a case here plus a
    /// matching `[[stitchable]]` function in `Foil.metal`.
    private static func shaderName(for treatment: CardFoilTreatment) -> String {
        switch treatment {
        case .etched: "grimoraFoilEtched"
        case .surge: "grimoraFoilSurge"
        case .halo: "grimoraFoilHalo"
        case .galaxy: "grimoraFoilGalaxy"
        case .oilSlick: "grimoraFoilOilSlick"
        case .confetti: "grimoraFoilConfetti"
        case .ripple: "grimoraFoilRipple"
        case .fracture: "grimoraFoilFracture"
        case .mana: "grimoraFoilManaGradient"
        case .neonInk: "grimoraFoilNeonInk"
        case .stepAndCompleat: "grimoraFoilStepCompleat"
        case .rainbow: "grimoraFoilRainbow"
        case .doubleRainbow: "grimoraFoilDoubleRainbow"
        case .silver: "grimoraFoilSilver"
        case .glossy: "grimoraFoilGlossy"
        case .gilded: "grimoraFoilGilded"
        case .textured: "grimoraFoilTextured"
        case .embossed: "grimoraFoilEmbossed"
        case .raised: "grimoraFoilRaised"
        default: "grimoraFoil"
        }
    }
}

#if os(iOS)
/// iOS foil: a self-animating drift from the shared `FoilClock` *plus* device-tilt modulation
/// from the gyro (shared stream), both offset/scaled per card so a grid never shimmers in
/// lockstep. The clock keeps the per-treatment effects (surge fire, neon darting, drifting
/// sparkles) alive when the phone is held still or running in a simulator with no gyro; tilting
/// then pushes the phase further so the card also "catches the light" as you angle it.
private struct MotionShaderFoilSheen: View {
    @ObservedObject private var motion = FoilMotionCenter.shared
    @ObservedObject private var clock = FoilClock.shared

    var seed: FoilSeed
    var treatment: CardFoilTreatment
    var intensity: Double
    var cornerRadius: CGFloat

    var body: some View {
        ShaderFoilSheen(
            phase: clock.time * CardFoilShimmerOverlay.driftRate * seed.speed
                + motion.phase * seed.speed
                + seed.phaseOffset,
            seed: seed,
            treatment: treatment,
            intensity: intensity,
            cornerRadius: cornerRadius
        )
        .onAppear { motion.subscribe(); clock.subscribe() }
        .onDisappear { motion.unsubscribe(); clock.unsubscribe() }
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
    var treatment: CardFoilTreatment
    var intensity: Double
    var cornerRadius: CGFloat

    var body: some View {
        ShaderFoilSheen(
            phase: clock.time * CardFoilShimmerOverlay.driftRate * seed.speed + seed.phaseOffset,
            seed: seed,
            treatment: treatment,
            intensity: intensity,
            cornerRadius: cornerRadius
        )
        .onAppear { clock.subscribe() }
        .onDisappear { clock.unsubscribe() }
    }
}
#endif
