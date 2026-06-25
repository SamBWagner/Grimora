import GrimoraCore
import SwiftUI

/// Desaturated, Magic-flavoured chip colours for the advanced-search rarity
/// toggles, tuned per colour scheme so they stay legible against the grouped
/// form. A selected chip fills with `fillColor`; `selectedForeground` is the
/// matching label colour with enough contrast on that fill. Unselected chips
/// reuse `fillColor` as their label tint so each rarity reads as itself even
/// before it is picked.
extension AdvancedSearchRarity {
    /// The rarity's chip colour for the given scheme.
    func fillColor(for colorScheme: ColorScheme) -> Color {
        let component = fillComponents(for: colorScheme)
        return Color(red: component.r, green: component.g, blue: component.b)
    }

    /// A label colour with sufficient contrast on `fillColor(for:)`.
    func selectedForeground(for colorScheme: ColorScheme) -> Color {
        let dark = Color(red: 0.09, green: 0.09, blue: 0.10)
        let light = Color(red: 0.97, green: 0.97, blue: 0.98)
        return switch (self, colorScheme) {
        case (.common, .dark): dark
        case (.common, _): light
        case (.uncommon, .dark): dark
        case (.uncommon, _): light
        case (.rare, _): dark
        case (.mythic, _): light
        }
    }

    /// Desaturated WUBRG-adjacent rarity colours, kept in the app's muted
    /// register: common neutral stone, uncommon steel/silver, rare gold (the
    /// same gold family the lists dashboard uses), mythic burnt orange.
    private func fillComponents(for colorScheme: ColorScheme) -> (r: Double, g: Double, b: Double) {
        switch (self, colorScheme) {
        case (.common, .dark): (0.64, 0.64, 0.66)
        case (.common, _): (0.40, 0.40, 0.43)
        case (.uncommon, .dark): (0.70, 0.74, 0.79)
        case (.uncommon, _): (0.46, 0.50, 0.56)
        case (.rare, .dark): (0.82, 0.66, 0.32)
        case (.rare, _): (0.70, 0.54, 0.22)
        case (.mythic, .dark): (0.81, 0.41, 0.22)
        case (.mythic, _): (0.74, 0.34, 0.16)
        }
    }
}
