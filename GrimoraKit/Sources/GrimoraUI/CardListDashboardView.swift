import GrimoraCore
import SwiftUI

struct CardListDashboardView: View {
    var stats: CardListDashboardStats
    var includesLands: Bool
    var palette: GrimoraPalette
    var onIncludesLandsChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()
                .overlay(palette.hairline.color)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    colorSection
                        .frame(width: 310, alignment: .leading)

                    dashboardDivider

                    valueSection
                        .frame(width: 180, alignment: .leading)

                    dashboardDivider

                    typeSection
                        .frame(width: 350, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    colorSection
                    valueSection
                    typeSection
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-list-dashboard")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Stats")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            Spacer(minLength: 0)

            Toggle("Include Lands", isOn: includesLandsBinding)
                .toggleStyle(.switch)
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("card-list-dashboard-include-lands-toggle")
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Colors")

            HStack(alignment: .center, spacing: 14) {
                CardListColorRingView(stats: stats, palette: palette)

                VStack(alignment: .leading, spacing: 7) {
                    if stats.colorDistribution.isEmpty {
                        Text("No color data")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                    } else {
                        ForEach(stats.colorDistribution) { colorStat in
                            CardListColorLegendRow(stat: colorStat, palette: palette)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Value")

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

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sectionTitle("Types")

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
                        CardListTypeRow(stat: typeStat, palette: palette)
                    }
                }
            }
        }
    }

    private var dashboardDivider: some View {
        Divider()
            .overlay(palette.hairline.color)
            .frame(height: 150)
    }

    private var includesLandsBinding: Binding<Bool> {
        Binding {
            includesLands
        } set: { newValue in
            onIncludesLandsChange(newValue)
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(palette.secondaryText.color)
            .textCase(.uppercase)
    }
}

private struct CardListColorRingView: View {
    var stats: CardListDashboardStats
    var palette: GrimoraPalette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.hairline.color.opacity(0.48), lineWidth: 16)

            ForEach(segments) { segment in
                CardListRingSliceShape(
                    startAngle: .degrees(segment.startDegrees),
                    endAngle: .degrees(segment.endDegrees)
                )
                .fill(color(for: segment.bucket))
            }

            VStack(spacing: 1) {
                Text(stats.totalQuantity.formatted())
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText.color)

                Text(stats.totalQuantity == 1 ? "card" : "cards")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .frame(width: 116, height: 116)
        .accessibilityLabel("Color distribution")
    }

    private var segments: [CardListRingSegment] {
        var start = -90.0
        var builtSegments: [CardListRingSegment] = []
        for stat in stats.colorDistribution {
            let span = max(0, stat.percentage) * 360
            builtSegments.append(
                CardListRingSegment(
                    bucket: stat.bucket,
                    startDegrees: start,
                    endDegrees: start + span
                )
            )
            start += span
        }
        return builtSegments
    }

    private func color(for bucket: CardListColorBucket) -> Color {
        switch bucket {
        case .white:
            Color(red: 0.95, green: 0.86, blue: 0.56)
        case .blue:
            Color(red: 0.26, green: 0.55, blue: 0.88)
        case .black:
            Color(red: 0.20, green: 0.18, blue: 0.20)
        case .red:
            Color(red: 0.82, green: 0.22, blue: 0.18)
        case .green:
            Color(red: 0.23, green: 0.62, blue: 0.35)
        case .multicolor:
            Color(red: 0.82, green: 0.55, blue: 0.20)
        case .colorless:
            Color(red: 0.58, green: 0.58, blue: 0.56)
        }
    }
}

private struct CardListRingSegment: Identifiable {
    var bucket: CardListColorBucket
    var startDegrees: Double
    var endDegrees: Double

    var id: CardListColorBucket {
        bucket
    }
}

private struct CardListRingSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let lineWidth = max(10, min(rect.width, rect.height) * 0.14)
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
}

private struct CardListColorLegendRow: View {
    var stat: CardListColorStat
    var palette: GrimoraPalette

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(stat.bucket.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(stat.percentage.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(1)
        }
    }

    private var color: Color {
        switch stat.bucket {
        case .white:
            Color(red: 0.95, green: 0.86, blue: 0.56)
        case .blue:
            Color(red: 0.26, green: 0.55, blue: 0.88)
        case .black:
            Color(red: 0.20, green: 0.18, blue: 0.20)
        case .red:
            Color(red: 0.82, green: 0.22, blue: 0.18)
        case .green:
            Color(red: 0.23, green: 0.62, blue: 0.35)
        case .multicolor:
            Color(red: 0.82, green: 0.55, blue: 0.20)
        case .colorless:
            Color(red: 0.58, green: 0.58, blue: 0.56)
        }
    }
}

private struct CardListTypeRow: View {
    var stat: CardListTypeStat
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
