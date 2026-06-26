import GrimoraCore
import SwiftUI

/// "Colors" section of the card list dashboard: a colour-distribution ring with a
/// legend of per-colour percentages.
struct CardCollectionDashboardColorSection: View {
    var stats: CardCollectionDashboardStats
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardCollectionDashboardSectionTitle(text: "Colors", palette: palette)

            HStack(alignment: .center, spacing: 14) {
                CardCollectionColorRingView(stats: stats, palette: palette)

                VStack(alignment: .leading, spacing: 7) {
                    if stats.colorDistribution.isEmpty {
                        Text("No color data")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                    } else {
                        ForEach(stats.colorDistribution) { colorStat in
                            CardCollectionColorLegendRow(stat: colorStat, palette: palette)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CardCollectionColorRingView: View {
    var stats: CardCollectionDashboardStats
    var palette: GrimoraPalette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.hairline.color.opacity(0.48), lineWidth: 16)

            ForEach(segments) { segment in
                CardCollectionRingSliceShape(
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

    private var segments: [CardCollectionRingSegment] {
        var start = -90.0
        var builtSegments: [CardCollectionRingSegment] = []
        for stat in stats.colorDistribution {
            let span = max(0, stat.percentage) * 360
            builtSegments.append(
                CardCollectionRingSegment(
                    bucket: stat.bucket,
                    startDegrees: start,
                    endDegrees: start + span
                )
            )
            start += span
        }
        return builtSegments
    }

    private func color(for bucket: CardCollectionColorBucket) -> Color {
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

private struct CardCollectionRingSegment: Identifiable {
    var bucket: CardCollectionColorBucket
    var startDegrees: Double
    var endDegrees: Double

    var id: CardCollectionColorBucket {
        bucket
    }
}

private struct CardCollectionRingSliceShape: Shape {
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

private struct CardCollectionColorLegendRow: View {
    var stat: CardCollectionColorStat
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
