import CoreGraphics
import SwiftUI

struct JumpToTopScrollState: Equatable {
    static let minimumOffset: CGFloat = 320
    static let viewportFraction: CGFloat = 0.75

    var contentOffsetY: CGFloat
    var viewportHeight: CGFloat

    init(contentOffsetY: CGFloat = 0, viewportHeight: CGFloat = 0) {
        self.contentOffsetY = contentOffsetY.isFinite ? contentOffsetY : 0
        self.viewportHeight = viewportHeight.isFinite ? viewportHeight : 0
    }

    static var top: JumpToTopScrollState {
        JumpToTopScrollState()
    }

    /// A canonical "button should show" state. Scroll tracking stores only this or `.top` — never the
    /// live per-frame offset — so the bound `@State` changes at most on a threshold crossing rather
    /// than on every scroll frame. Nothing reads the raw offset/viewport (only `showsButton`), so a
    /// canonical value is behaviour-identical. `minimumOffset` clears the `>= threshold` bar.
    static var showingButton: JumpToTopScrollState {
        JumpToTopScrollState(contentOffsetY: minimumOffset, viewportHeight: 0)
    }

    var showsButton: Bool {
        Self.showsButton(contentOffsetY: contentOffsetY, viewportHeight: viewportHeight)
    }

    static func showsButton(contentOffsetY: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard contentOffsetY.isFinite,
              viewportHeight.isFinite,
              contentOffsetY > 0
        else {
            return false
        }

        let threshold = max(minimumOffset, max(0, viewportHeight) * viewportFraction)
        return contentOffsetY >= threshold
    }
}

private struct JumpToTopButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var accessibilityIdentifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Jump to Top", systemImage: "arrow.up.to.line")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: controlSize, height: controlSize)
        }
        .buttonStyle(JumpToTopButtonStyle(palette: palette))
        .help("Jump to Top")
        .accessibilityLabel("Jump to Top")
        .accessibilityHint("Scrolls to the top of the current list")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var controlSize: CGFloat {
        #if os(visionOS)
        60
        #else
        44
        #endif
    }
}

private struct JumpToTopButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var palette: GrimoraPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.primaryText.color)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        configuration.isPressed
                            ? palette.accent.color.opacity(0.58)
                            : palette.hairline.color.opacity(0.82),
                        lineWidth: 1
                    )
            }
            .shadow(color: palette.shadow.color.opacity(0.32), radius: 12, x: 0, y: 5)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.pressSpring,
                value: configuration.isPressed
            )
    }
}

extension View {
    func jumpToTopButtonInset(
        isVisible: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            JumpToTopButtonInsetModifier(
                isVisible: isVisible,
                accessibilityIdentifier: accessibilityIdentifier,
                action: action
            )
        )
    }

    func jumpToTopScrollTracking(_ state: Binding<JumpToTopScrollState>) -> some View {
        modifier(JumpToTopScrollTrackingModifier(state: state))
    }

    @ViewBuilder
    func jumpToTopLegacyOffsetReader(coordinateSpaceName: String) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            self
        } else {
            background {
                GeometryReader { proxy in
                    let contentOffsetY = max(0, -proxy.frame(in: .named(coordinateSpaceName)).minY)
                    Color.clear.preference(
                        key: JumpToTopScrollStatePreferenceKey.self,
                        value: JumpToTopScrollState(contentOffsetY: contentOffsetY)
                    )
                }
            }
        }
        #else
        self
        #endif
    }
}

private struct JumpToTopButtonInsetModifier: ViewModifier {
    var isVisible: Bool
    var accessibilityIdentifier: String
    var action: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            if isVisible {
                JumpToTopButton(
                    accessibilityIdentifier: accessibilityIdentifier,
                    action: action
                )
                .padding(.trailing, horizontalPadding)
                .padding(.bottom, bottomPadding)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isVisible)
    }

    private var horizontalPadding: CGFloat {
        #if os(visionOS)
        28
        #else
        18
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(visionOS)
        24
        #else
        16
        #endif
    }
}

private struct JumpToTopScrollTrackingModifier: ViewModifier {
    @Binding var state: JumpToTopScrollState

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    JumpToTopScrollState.showsButton(
                        contentOffsetY: geometry.contentOffset.y,
                        viewportHeight: geometry.containerSize.height
                    )
                } action: { _, showsButton in
                    applyButtonVisibility(showsButton)
                }
        } else {
            content
                .onPreferenceChange(JumpToTopScrollStatePreferenceKey.self) { newState in
                    applyButtonVisibility(newState.showsButton)
                }
        }
        #else
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                JumpToTopScrollState.showsButton(
                    contentOffsetY: geometry.contentOffset.y,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, showsButton in
                applyButtonVisibility(showsButton)
            }
        #endif
    }

    /// Only writes the bound state when the button's visibility actually flips. Tracking a `Bool`
    /// (rather than the raw offset) means `onScrollGeometryChange` fires this at most twice per
    /// scroll — a threshold crossing each way — instead of every frame, which was re-evaluating the
    /// whole list-detail body (snapshot rebuild + grid re-pack) on every scroll tick.
    private func applyButtonVisibility(_ showsButton: Bool) {
        guard state.showsButton != showsButton else {
            return
        }
        state = showsButton ? .showingButton : .top
    }
}

struct JumpToTopScrollStatePreferenceKey: PreferenceKey {
    static let defaultValue = JumpToTopScrollState.top

    static func reduce(value: inout JumpToTopScrollState, nextValue: () -> JumpToTopScrollState) {
        value = nextValue()
    }
}
