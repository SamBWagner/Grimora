import SwiftUI
#if os(iOS)
import CoreMotion
#endif

/// A synthetic holographic foil sheen drawn over card artwork. Scryfall does not
/// host foil versions of card art, so foil is rendered here rather than fetched.
///
/// The treatment is tiered:
/// - iOS: a holographic wash whose hue + specular highlight track device tilt
///   (Core Motion), so the card "catches the light" as you move the phone.
/// - visionOS: a gently auto-animated sweep (device-tilt attitude isn't surfaced
///   the same way).
/// - macOS: a fixed diagonal sheen.
/// - Reduce Motion (any platform): the fixed diagonal sheen.
struct CardFoilOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cornerRadius: CGFloat = 8

    /// The resting phase used for all static treatments, chosen so the specular
    /// band sits across the card rather than tucked into a corner.
    static let restingPhase = 0.35

    var body: some View {
        #if os(iOS)
        if reduceMotion {
            FoilSheen(phase: Self.restingPhase, cornerRadius: cornerRadius)
        } else {
            MotionFoilSheen(cornerRadius: cornerRadius)
        }
        #elseif os(visionOS)
        if reduceMotion {
            FoilSheen(phase: Self.restingPhase, cornerRadius: cornerRadius)
        } else {
            AnimatedFoilSheen(cornerRadius: cornerRadius)
        }
        #else
        FoilSheen(phase: Self.restingPhase, cornerRadius: cornerRadius)
        #endif
    }
}

/// The stateless visual. `phase` (0...1) shifts the rainbow hue and slides the
/// specular highlight diagonally across the card.
private struct FoilSheen: View {
    var phase: Double
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            LinearGradient(
                colors: Self.rainbow(phase: phase),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
            .opacity(0.22)

            specularBand
                .blendMode(.screen)
                .opacity(0.45)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var specularBand: some View {
        let p = phase - floor(phase)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, p - 0.18)),
                .init(color: .white.opacity(0.85), location: min(max(p, 0.0001), 0.9999)),
                .init(color: .clear, location: min(1, p + 0.18))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A six-stop rainbow whose hues rotate with `phase` for the holographic wash.
    static func rainbow(phase: Double) -> [Color] {
        stride(from: 0.0, to: 1.0, by: 1.0 / 6.0).map { base in
            let hue = (base + phase).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: 0.85, brightness: 1)
        }
    }
}

#if os(visionOS)
/// visionOS fallback: a slow continuous sweep using the render timeline.
private struct AnimatedFoilSheen: View {
    var cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = (seconds / 4).truncatingRemainder(dividingBy: 1)
            FoilSheen(phase: phase, cornerRadius: cornerRadius)
        }
    }
}
#endif

#if os(iOS)
/// iOS: drives the sheen from device attitude so tilting the phone moves the foil.
private struct MotionFoilSheen: View {
    var cornerRadius: CGFloat
    @ObservedObject private var motion = FoilMotionCenter.shared

    var body: some View {
        FoilSheen(phase: motion.phase, cornerRadius: cornerRadius)
            .animation(.easeOut(duration: 0.12), value: motion.phase)
            .onAppear { motion.subscribe() }
            .onDisappear { motion.unsubscribe() }
    }
}

/// A single shared Core Motion source so any number of on-screen foil cards read
/// one device-motion stream. Ref-counted: the gyroscope only runs while at least
/// one foil overlay is visible.
@MainActor
private final class FoilMotionCenter: ObservableObject {
    static let shared = FoilMotionCenter()

    @Published private(set) var phase: Double = CardFoilOverlay.restingPhase

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
        phase = CardFoilOverlay.restingPhase
    }
}
#endif
