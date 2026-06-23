import GrimoraCore
import SwiftUI

/// Page-control style dot strip under the compact printings pager so it reads as
/// swipeable. The dots sit on a material capsule so they stay legible over light
/// or dark artwork, and the strip windows down for cards with many printings.
///
/// Extracted into its own view so swiping the pager re-renders only the strip,
/// not the whole card detail body. Windowing/sizing stay in the pure
/// `compactPrintingDotWindow` / `compactPrintingDotDiameter` helpers.
struct CardPrintingPageIndicator: View {
    let ids: [CardRecord.ID]
    let currentID: CardRecord.ID
    var palette: GrimoraPalette

    private static let maxVisibleDots = 7

    var body: some View {
        let currentIndex = ids.firstIndex(of: currentID) ?? 0
        let window = compactPrintingDotWindow(
            count: ids.count, current: currentIndex, maxVisible: Self.maxVisibleDots)
        return HStack(spacing: 6) {
            ForEach(Array(window), id: \.self) { index in
                let diameter = compactPrintingDotDiameter(
                    index: index, current: currentIndex, count: ids.count, window: window)
                Circle()
                    .fill(palette.primaryText.color.opacity(index == currentIndex ? 1 : 0.3))
                    .frame(width: diameter, height: diameter)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: currentIndex)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(palette.hairline.color.opacity(0.5), lineWidth: 0.5)
        }
        .accessibilityElement()
        .accessibilityLabel("Printing \(currentIndex + 1) of \(ids.count)")
        .accessibilityIdentifier("card-printings-page-indicator")
    }
}
