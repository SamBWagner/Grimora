import SwiftUI

struct GrimoraColorValue: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct GrimoraPalette: Equatable, Sendable {
    var appBackground: GrimoraColorValue
    var sidebarBackground: GrimoraColorValue
    var cardSurface: GrimoraColorValue
    var primaryText: GrimoraColorValue
    var secondaryText: GrimoraColorValue
    var accent: GrimoraColorValue
    var selectedAccent: GrimoraColorValue
    var placeholderFill: GrimoraColorValue
    var hairline: GrimoraColorValue
    var shadow: GrimoraColorValue
    // Muted, theme-tuned tints for live search-syntax clause colouring.
    var syntaxValid: GrimoraColorValue
    var syntaxInvalid: GrimoraColorValue
    var syntaxIncomplete: GrimoraColorValue

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            appBackground = GrimoraColorValue(red: 0.0, green: 0.0, blue: 0.0)
            sidebarBackground = GrimoraColorValue(red: 0.055, green: 0.055, blue: 0.060)
            cardSurface = GrimoraColorValue(red: 0.090, green: 0.090, blue: 0.100)
            primaryText = GrimoraColorValue(red: 0.960, green: 0.960, blue: 0.970)
            secondaryText = GrimoraColorValue(red: 0.680, green: 0.680, blue: 0.700)
            accent = GrimoraColorValue(red: 0.735, green: 0.610, blue: 0.820)
            selectedAccent = GrimoraColorValue(red: 0.310, green: 0.205, blue: 0.390)
            placeholderFill = GrimoraColorValue(red: 0.145, green: 0.145, blue: 0.155)
            hairline = GrimoraColorValue(red: 0.370, green: 0.370, blue: 0.390, opacity: 0.45)
            shadow = GrimoraColorValue(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.34)
            syntaxValid = GrimoraColorValue(red: 0.560, green: 0.745, blue: 0.620)
            syntaxInvalid = GrimoraColorValue(red: 0.875, green: 0.525, blue: 0.545)
            syntaxIncomplete = GrimoraColorValue(red: 0.865, green: 0.745, blue: 0.520)
        default:
            appBackground = GrimoraColorValue(red: 1.0, green: 1.0, blue: 1.0)
            sidebarBackground = GrimoraColorValue(red: 0.955, green: 0.955, blue: 0.970)
            cardSurface = GrimoraColorValue(red: 1.0, green: 1.0, blue: 1.0)
            primaryText = GrimoraColorValue(red: 0.070, green: 0.070, blue: 0.080)
            secondaryText = GrimoraColorValue(red: 0.420, green: 0.420, blue: 0.440)
            accent = GrimoraColorValue(red: 0.260, green: 0.155, blue: 0.325)
            selectedAccent = GrimoraColorValue(red: 0.900, green: 0.850, blue: 0.760)
            placeholderFill = GrimoraColorValue(red: 0.925, green: 0.925, blue: 0.940)
            hairline = GrimoraColorValue(red: 0.620, green: 0.620, blue: 0.650, opacity: 0.30)
            shadow = GrimoraColorValue(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.14)
            syntaxValid = GrimoraColorValue(red: 0.235, green: 0.495, blue: 0.345)
            syntaxInvalid = GrimoraColorValue(red: 0.690, green: 0.235, blue: 0.290)
            syntaxIncomplete = GrimoraColorValue(red: 0.585, green: 0.435, blue: 0.140)
        }
    }
}

extension GrimoraPalette {
    static let light = GrimoraPalette(colorScheme: .light)
    static let dark = GrimoraPalette(colorScheme: .dark)

    /// The palette is derived purely from the colour scheme, so there are only ever two instances.
    /// Returning the cached statics avoids rebuilding 13 colour values every time a card cell's
    /// `body` is evaluated (it was being reconstructed several times per cell, per render).
    static func cached(for colorScheme: ColorScheme) -> GrimoraPalette {
        colorScheme == .dark ? .dark : .light
    }
}
