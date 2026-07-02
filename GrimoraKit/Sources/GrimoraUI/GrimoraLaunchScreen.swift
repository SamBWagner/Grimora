import SwiftUI

/// The cold-start launch screen: the open grimoire from the app icon resting over a
/// living, glassy blue-purple vortex. Instead of the bare black window that used to
/// greet the app on open, the book fades up over slowly-turning swirls that echo the
/// teal orb behind the icon's book.
///
/// Motion is split two ways: the swirls and glow are driven by a `TimelineView` so they
/// flow smoothly and independently of view state, while the book itself gets a one-shot
/// spring entrance. When Reduce Motion is on, the timeline is paused (a single static
/// frame of the vortex) and the book simply fades in without scaling.
struct GrimoraLaunchScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The launch screen is skipped under UI tests (a lingering splash hides the seeded
    /// search UI) and whenever it's explicitly disabled.
    static var isDisabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["GRIMORA_DISABLE_LAUNCH_SCREEN"] == "1"
            || environment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let logoSize = max(140, min(300, side * 0.4))

            ZStack {
                GrimoraLaunchPalette.baseGradient
                    .ignoresSafeArea()

                SwirlVortex(reduceMotion: reduceMotion)
                    .opacity(appeared ? 1 : 0)

                logo(size: logoSize)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Grimora")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("launch-screen")
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) {
                    appeared = true
                }
            }
        }
    }

    private func logo(size: CGFloat) -> some View {
        GrimoraLogoView(size: size)
            .shadow(color: GrimoraLaunchPalette.teal.opacity(0.55), radius: 34, x: 0, y: 0)
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 16)
            .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.82))
            .opacity(appeared ? 1 : 0)
    }
}

/// The branded colours behind the launch screen — pulled from the app icon so the splash
/// reads as an extension of it rather than the system window background.
private enum GrimoraLaunchPalette {
    static let topPurple = Color(red: 0.21, green: 0.15, blue: 0.36)
    static let midnight = Color(red: 0.09, green: 0.10, blue: 0.30)
    static let deepBlue = Color(red: 0.06, green: 0.09, blue: 0.34)
    static let teal = Color(red: 0.18, green: 0.72, blue: 0.78)
    static let lilac = Color(red: 0.73, green: 0.61, blue: 0.90)
    static let electricBlue = Color(red: 0.30, green: 0.44, blue: 0.96)

    static let baseGradient = LinearGradient(
        colors: [topPurple, midnight, deepBlue],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// The glassy, slowly-turning swirl field. Three blurred pinwheel gradients (teal, lilac,
/// electric blue) rotate at different speeds and directions and are additively composited,
/// giving a glassy nebula that concentrates behind the logo and dissolves toward the edges.
/// Expanding ripple rings echo the concentric orb in the icon.
private struct SwirlVortex: View {
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let extent = max(size.width, size.height)

            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = reduceMotion ? 0.5 : (0.5 + 0.5 * sin(t * 0.9))

                ZStack {
                    centralGlow(extent: extent, pulse: pulse)

                    ZStack {
                        arm(color: GrimoraLaunchPalette.teal, angle: t * 13, extent: extent * 1.25,
                            blur: 34, opacity: 0.85, arms: 2)
                        arm(color: GrimoraLaunchPalette.lilac, angle: -t * 8 + 55, extent: extent * 1.6,
                            blur: 52, opacity: 0.62, arms: 3)
                        arm(color: GrimoraLaunchPalette.electricBlue, angle: t * 5 + 120, extent: extent * 2.0,
                            blur: 80, opacity: 0.5, arms: 2)
                    }
                    .mask(vortexMask(extent: extent))
                    .blendMode(.plusLighter)

                    ripples(t: t, extent: extent)
                        .blendMode(.plusLighter)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A soft breathing bloom of light directly behind the book.
    private func centralGlow(extent: CGFloat, pulse: Double) -> some View {
        RadialGradient(
            colors: [
                GrimoraLaunchPalette.teal.opacity(0.42),
                GrimoraLaunchPalette.electricBlue.opacity(0.16),
                .clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: extent * (0.28 + 0.05 * pulse)
        )
        .blendMode(.plusLighter)
        .opacity(0.6 + 0.3 * pulse)
    }

    /// One rotating pinwheel: an angular gradient with `arms` luminous spokes, blown up past
    /// the frame and heavily blurred into a glassy smear.
    private func arm(
        color: Color,
        angle: Double,
        extent: CGFloat,
        blur: CGFloat,
        opacity: Double,
        arms: Int
    ) -> some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: spokeStops(color: color, arms: arms)),
                    center: .center
                )
            )
            .frame(width: extent, height: extent)
            .rotationEffect(.degrees(angle))
            .blur(radius: blur)
            .opacity(opacity)
    }

    /// Evenly-spaced soft spokes around the circle: each arm ramps up to the colour then back
    /// to clear, so the rotating gradient reads as swirling light rather than hard wedges.
    private func spokeStops(color: Color, arms: Int) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let span = 1.0 / Double(arms)
        for index in 0..<arms {
            let base = Double(index) * span
            stops.append(.init(color: .clear, location: base))
            stops.append(.init(color: color, location: base + span * 0.22))
            stops.append(.init(color: .clear, location: base + span * 0.5))
        }
        stops.append(.init(color: .clear, location: 1))
        return stops
    }

    /// Concentrates the swirls behind the logo and fades them out toward the corners so the
    /// vortex feels centred on the book, glass dissolving into the deep background.
    private func vortexMask(extent: CGFloat) -> some View {
        RadialGradient(
            colors: [.white, .white.opacity(0.9), .white.opacity(0.4), .clear],
            center: .center,
            startRadius: 0,
            endRadius: extent * 0.72
        )
    }

    /// Concentric rings expanding outward and fading, echoing the icon's rippling orb.
    private func ripples(t: Double, extent: CGFloat) -> some View {
        let count = 3
        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let cycle = 4.6
                let phase = reduceMotion
                    ? Double(index) / Double(count)
                    : ((t / cycle) + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
                let diameter = extent * (0.24 + 0.62 * phase)

                Circle()
                    .stroke(GrimoraLaunchPalette.teal.opacity(0.5), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                    .opacity((1 - phase) * 0.7)
            }
        }
    }
}

#Preview("Launch") {
    GrimoraLaunchScreen()
        .frame(width: 900, height: 650)
}
