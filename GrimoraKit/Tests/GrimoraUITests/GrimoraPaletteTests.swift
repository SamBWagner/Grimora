@testable import GrimoraUI
import XCTest

final class GrimoraPaletteTests: XCTestCase {
    func testLightAndDarkPalettesUseDifferentSemanticColors() {
        XCTAssertNotEqual(GrimoraPalette.light.appBackground, GrimoraPalette.dark.appBackground)
        XCTAssertNotEqual(GrimoraPalette.light.sidebarBackground, GrimoraPalette.dark.sidebarBackground)
        XCTAssertNotEqual(GrimoraPalette.light.cardSurface, GrimoraPalette.dark.cardSurface)
        XCTAssertNotEqual(GrimoraPalette.light.placeholderFill, GrimoraPalette.dark.placeholderFill)
    }

    func testBackgroundAndSurfaceColorsAreNeutral() {
        for color in neutralSurfaceColors {
            XCTAssertLessThanOrEqual(channelSpread(color), 0.02)
        }
    }

    func testAppBackgroundsUseSimpleLightAndDarkExtremes() {
        XCTAssertEqual(GrimoraPalette.dark.appBackground, GrimoraColorValue(red: 0, green: 0, blue: 0))
        XCTAssertEqual(GrimoraPalette.light.appBackground, GrimoraColorValue(red: 1, green: 1, blue: 1))
    }

    func testPrimaryTextContrastsAgainstBackgrounds() {
        XCTAssertGreaterThanOrEqual(contrast(GrimoraPalette.light.primaryText, GrimoraPalette.light.appBackground), 7)
        XCTAssertGreaterThanOrEqual(contrast(GrimoraPalette.light.primaryText, GrimoraPalette.light.cardSurface), 7)
        XCTAssertGreaterThanOrEqual(contrast(GrimoraPalette.dark.primaryText, GrimoraPalette.dark.appBackground), 7)
        XCTAssertGreaterThanOrEqual(contrast(GrimoraPalette.dark.primaryText, GrimoraPalette.dark.cardSurface), 7)
    }

    func testAccentIsNotUsedAsASurfaceColor() {
        XCTAssertNotEqual(GrimoraPalette.light.accent, GrimoraPalette.light.appBackground)
        XCTAssertNotEqual(GrimoraPalette.light.accent, GrimoraPalette.light.cardSurface)
        XCTAssertNotEqual(GrimoraPalette.dark.accent, GrimoraPalette.dark.appBackground)
        XCTAssertNotEqual(GrimoraPalette.dark.accent, GrimoraPalette.dark.cardSurface)
    }

    func testPlaceholderColorsAreMutedAgainstText() {
        XCTAssertLessThan(contrast(GrimoraPalette.light.placeholderFill, GrimoraPalette.light.appBackground), 1.5)
        XCTAssertLessThan(contrast(GrimoraPalette.dark.placeholderFill, GrimoraPalette.dark.appBackground), 1.8)
        XCTAssertGreaterThanOrEqual(contrast(GrimoraPalette.light.secondaryText, GrimoraPalette.light.placeholderFill), 3)
        XCTAssertGreaterThanOrEqual(contrast(GrimoraPalette.dark.secondaryText, GrimoraPalette.dark.placeholderFill), 3)
    }

    private func contrast(_ first: GrimoraColorValue, _ second: GrimoraColorValue) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func luminance(_ value: GrimoraColorValue) -> Double {
        let red = linear(value.red)
        let green = linear(value.green)
        let blue = linear(value.blue)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private var neutralSurfaceColors: [GrimoraColorValue] {
        [
            GrimoraPalette.light.appBackground,
            GrimoraPalette.light.sidebarBackground,
            GrimoraPalette.light.cardSurface,
            GrimoraPalette.light.placeholderFill,
            GrimoraPalette.dark.appBackground,
            GrimoraPalette.dark.sidebarBackground,
            GrimoraPalette.dark.cardSurface,
            GrimoraPalette.dark.placeholderFill
        ]
    }

    private func channelSpread(_ value: GrimoraColorValue) -> Double {
        let channels = [value.red, value.green, value.blue]
        return (channels.max() ?? 0) - (channels.min() ?? 0)
    }

    private func linear(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }
}
