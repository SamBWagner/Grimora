import GrimoraCore
import SwiftUI

/// "Types" section of the card list dashboard: the top five card types with
/// quantity, percentage, and a proportional bar.
struct CardCollectionDashboardTypeSection: View {
    var stats: CardCollectionDashboardStats
    var includesLands: Bool
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CardCollectionDashboardSectionTitle(text: "Types", palette: palette)

                Spacer(minLength: 0)

                Text("Top 5")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
            }

            if stats.topTypes.isEmpty {
                Text(includesLands ? "No type data" : "No nonland types")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stats.topTypes) { typeStat in
                        CardCollectionTypeRow(stat: typeStat, palette: palette)
                    }
                }
            }
        }
    }
}

private struct CardCollectionTypeRow: View {
    var stat: CardCollectionTypeStat
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stat.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(stat.quantity.formatted())
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)

                Text(stat.percentage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .frame(width: 42, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.hairline.color.opacity(0.42))

                    Capsule()
                        .fill(palette.accent.color.opacity(0.74))
                        .frame(width: max(0, proxy.size.width * min(max(stat.percentage, 0), 1)))
                }
            }
            .frame(height: 6)
        }
    }
}
