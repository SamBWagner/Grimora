import SwiftUI

/// Shared chrome for the app's circular floating buttons: a material disc with a
/// hairline border and a soft shadow, sized for touch. Used by the macOS
/// Advanced Search launch button and the touch search-options gear FAB so they
/// match.
struct FloatingCircleChrome: ViewModifier {
    var palette: GrimoraPalette
    @ScaledMetric private var diameter: Double = 52

    func body(content: Content) -> some View {
        content
            .font(.title2)
            .foregroundStyle(palette.accent.color)
            .frame(width: diameter, height: diameter)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(palette.hairline.color, lineWidth: 1)
            }
            .shadow(color: palette.shadow.color.opacity(0.18), radius: 5, x: 0, y: 3)
    }
}

extension View {
    /// Wraps an icon in the shared circular floating-button chrome.
    func floatingCircleChrome(palette: GrimoraPalette) -> some View {
        modifier(FloatingCircleChrome(palette: palette))
    }
}
