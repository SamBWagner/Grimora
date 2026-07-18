import GrimoraCore
import SwiftUI

/// Concrete colours for the curated `LabelColor` palette, tuned per colour scheme so label pips and
/// swatches stay distinct at small sizes while keeping the app's muted register (mirrors how
/// `RarityColor` styles the rarity chips). `fillColor` paints the pip/swatch; `onFillColor` is a
/// contrast-aware label colour for when a label is drawn as a filled name chip.
extension LabelColor {
    /// The pip / swatch colour for the given scheme.
    func fillColor(for colorScheme: ColorScheme) -> Color {
        let component = fillComponents(for: colorScheme)
        return Color(red: component.r, green: component.g, blue: component.b)
    }

    /// A foreground colour with sufficient contrast on `fillColor(for:)`, picked by the fill's
    /// relative luminance so bright fills get dark text and deep fills get light text.
    func onFillColor(for colorScheme: ColorScheme) -> Color {
        let component = fillComponents(for: colorScheme)
        let luminance = 0.2126 * component.r + 0.7152 * component.g + 0.0722 * component.b
        return luminance > 0.6
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    /// Slightly saturated but not neon — distinct enough to tell apart as small dots, restrained
    /// enough to match the app. The `purple` is a lavender/violet kept clear of the app's accent
    /// purple, which is only used for selection chrome.
    private func fillComponents(for colorScheme: ColorScheme) -> (r: Double, g: Double, b: Double) {
        switch (self, colorScheme) {
        case (.green, .dark): (0.42, 0.72, 0.45)
        case (.green, _): (0.26, 0.58, 0.33)
        case (.red, .dark): (0.88, 0.42, 0.42)
        case (.red, _): (0.78, 0.26, 0.26)
        case (.blue, .dark): (0.40, 0.63, 0.92)
        case (.blue, _): (0.20, 0.47, 0.82)
        case (.amber, .dark): (0.92, 0.73, 0.31)
        case (.amber, _): (0.80, 0.59, 0.16)
        case (.purple, .dark): (0.68, 0.50, 0.88)
        case (.purple, _): (0.52, 0.34, 0.78)
        case (.orange, .dark): (0.93, 0.57, 0.31)
        case (.orange, _): (0.86, 0.45, 0.19)
        case (.teal, .dark): (0.34, 0.75, 0.73)
        case (.teal, _): (0.16, 0.57, 0.56)
        case (.pink, .dark): (0.93, 0.55, 0.73)
        case (.pink, _): (0.84, 0.38, 0.62)
        case (.grey, .dark): (0.62, 0.64, 0.68)
        case (.grey, _): (0.47, 0.49, 0.54)
        }
    }
}
