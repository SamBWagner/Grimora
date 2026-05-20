import SwiftUI

enum GrimoraInteraction {
    static let hoverSpring = Animation.spring(response: 0.24, dampingFraction: 0.78)
    static let pressSpring = Animation.spring(response: 0.16, dampingFraction: 0.72)
    static let focusAnimation = Animation.easeInOut(duration: 0.14)

    static let cardHoverScale: CGFloat = 1.025
    static let controlPressedScale: CGFloat = 0.92
    static let compactPressedScale: CGFloat = 0.985
}

enum GrimoraControlTone {
    case normal
    case destructive

    func foregroundColor(palette: GrimoraPalette) -> Color {
        switch self {
        case .normal:
            palette.primaryText.color
        case .destructive:
            .red
        }
    }

    func accentColor(palette: GrimoraPalette) -> Color {
        switch self {
        case .normal:
            palette.accent.color
        case .destructive:
            .red
        }
    }
}

extension View {
    func grimoraGridCardInteraction(isHovered: Binding<Bool>) -> some View {
        modifier(GrimoraGridCardInteractionModifier(isHovered: isHovered))
    }

    func grimoraSidebarRowHover(
        isHovered: Binding<Bool>,
        palette: GrimoraPalette,
        isSelected: Bool
    ) -> some View {
        modifier(
            GrimoraSidebarRowHoverModifier(
                isHovered: isHovered,
                palette: palette,
                isSelected: isSelected
            )
        )
    }

    func grimoraDropSuccessFeedback(trigger: Int) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }

    func grimoraSelectionFeedback(trigger: Int) -> some View {
        sensoryFeedback(.selection, trigger: trigger)
    }

    func grimoraOpenFeedback(trigger: Int) -> some View {
        sensoryFeedback(.selection, trigger: trigger)
    }

    func grimoraIncreaseFeedback(trigger: Int) -> some View {
        sensoryFeedback(.increase, trigger: trigger)
    }

    func grimoraDecreaseFeedback(trigger: Int) -> some View {
        sensoryFeedback(.decrease, trigger: trigger)
    }

    func grimoraSuccessFeedback(trigger: Int) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }
}

private struct GrimoraGridCardInteractionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .scaleEffect(isHovered && !reduceMotion ? GrimoraInteraction.cardHoverScale : 1)
            .zIndex(isHovered ? 1 : 0)
            .animation(reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.hoverSpring, value: isHovered)
            .onHover { isHovered = $0 }
        #elseif os(iOS)
        content
            .hoverEffect(.lift)
        #else
        content
        #endif
    }
}

private struct GrimoraSidebarRowHoverModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isHovered: Bool
    var palette: GrimoraPalette
    var isSelected: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoverFill)
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.012 : 1)
            .animation(reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.hoverSpring, value: isHovered)
            .onHover { isHovered = $0 }
        #else
        content
        #endif
    }

    private var hoverFill: Color {
        guard isHovered, !isSelected else {
            return Color.clear
        }
        return palette.cardSurface.color.opacity(0.42)
    }
}

struct GrimoraIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? GrimoraInteraction.controlPressedScale : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(
                reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.pressSpring,
                value: configuration.isPressed
            )
    }
}

struct GrimoraFloatingActionIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var title: String
    var systemName: String
    var palette: GrimoraPalette
    var foregroundColor: Color?
    var feedbackTrigger = 0

    var body: some View {
        decoratedIcon
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Circle())
            #if os(iOS)
            .hoverEffect(.lift)
            #endif
    }

    @ViewBuilder
    private var decoratedIcon: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            icon
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    Circle()
                        .stroke(palette.hairline.color.opacity(0.78), lineWidth: 1)
                }
                .shadow(color: palette.shadow.color.opacity(0.42), radius: 10, x: 0, y: 5)
        } else {
            fallbackIcon
        }
        #else
        fallbackIcon
        #endif
    }

    private var fallbackIcon: some View {
        icon
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(palette.hairline.color.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: palette.shadow.color.opacity(0.42), radius: 10, x: 0, y: 5)
    }

    private var icon: some View {
        Label(title, systemImage: systemName)
            .labelStyle(.iconOnly)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foregroundColor ?? palette.accent.color)
            .symbolEffect(.bounce, value: reduceMotion ? 0 : feedbackTrigger)
            .frame(width: 44, height: 44)
            .accessibilityLabel(title)
    }
}

struct GrimoraCompactSurfaceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var palette: GrimoraPalette
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        configuration.isPressed
                            ? palette.accent.color.opacity(0.5)
                            : palette.hairline.color,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? GrimoraInteraction.compactPressedScale : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.pressSpring,
                value: configuration.isPressed
            )
    }
}

struct GrimoraCapsuleSurfaceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var palette: GrimoraPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        configuration.isPressed
                            ? palette.accent.color.opacity(0.5)
                            : palette.hairline.color,
                        lineWidth: 1
                    )
            }
            .clipShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? GrimoraInteraction.compactPressedScale : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.pressSpring,
                value: configuration.isPressed
            )
    }
}

struct GrimoraSidebarNavigationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var isSelected: Bool
    var palette: GrimoraPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? palette.primaryText.color : palette.secondaryText.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor(isPressed: configuration.isPressed), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.pressSpring,
                value: configuration.isPressed
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return palette.selectedAccent.color.opacity(isPressed ? 0.72 : 0.58)
        }
        return isPressed ? palette.accent.color.opacity(0.12) : Color.clear
    }

    private func strokeColor(isPressed: Bool) -> Color {
        if isSelected {
            return palette.accent.color.opacity(isPressed ? 0.5 : 0.32)
        }
        return isPressed ? palette.accent.color.opacity(0.28) : Color.clear
    }
}
