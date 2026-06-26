import GrimoraCore
import SwiftUI

/// "Value" section of the card list dashboard: the total USD value plus a note on
/// how many cards were priced vs. skipped.
struct CardCollectionDashboardValueSection: View {
    var stats: CardCollectionDashboardStats
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardCollectionDashboardSectionTitle(text: "Value", palette: palette)

            Text(stats.totalPriceUSD, format: .currency(code: "USD"))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityIdentifier("card-list-dashboard-total-value")

            Label(pricingNote, systemImage: pricingIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(pricingNoteColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("card-list-dashboard-pricing-note")
        }
    }

    private var pricingNote: String {
        let skippedQuantity = stats.unpricedQuantity + stats.unavailableQuantity
        if skippedQuantity == 0 {
            let noun = stats.pricedQuantity == 1 ? "card" : "cards"
            return "\(stats.pricedQuantity.formatted()) priced \(noun)"
        }

        let noun = skippedQuantity == 1 ? "card" : "cards"
        return "\(skippedQuantity.formatted()) \(noun) unpriced/unavailable"
    }

    private var pricingIcon: String {
        stats.unpricedQuantity + stats.unavailableQuantity == 0 ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var pricingNoteColor: Color {
        stats.unpricedQuantity + stats.unavailableQuantity == 0 ? palette.secondaryText.color : .orange
    }
}
