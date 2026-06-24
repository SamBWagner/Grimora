import Charts
import SwiftUI

/// The 90-day price-history line chart with interactive scrubbing. Owns the
/// scrub/share state internally so dragging the plot updates only this view,
/// not the whole card detail body. Pricing/formatting is supplied by the host as
/// closures so currency conversion stays in one place.
struct CardValueHistoryChart: View {
    let points: [CardValueChartPoint]
    var palette: GrimoraPalette
    @Binding var detailFeedbackTrigger: Int
    @Binding var shareFeedbackTrigger: Int
    var priceText: (Double?) -> String
    var compactPriceText: (Double) -> String
    var dateText: (Date) -> String
    var snapshotText: (CardValueChartPoint) -> String

    @State private var scrubbedValuePoint: CardValueChartPoint?
    @State private var valueHistoryShareItem: PriceHistoryShareItem?

    @ViewBuilder
    var body: some View {
        if points.count > 1 {
            VStack {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.price)
                        )
                        .foregroundStyle(palette.accent.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    if let scrubbed = scrubbedValuePoint {
                        RuleMark(x: .value("Date", scrubbed.date))
                            .foregroundStyle(palette.secondaryText.color.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(
                                position: .top,
                                spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                scrubReadout(for: scrubbed)
                            }

                        PointMark(
                            x: .value("Date", scrubbed.date),
                            y: .value("Price", scrubbed.price)
                        )
                        .foregroundStyle(palette.accent.color)
                        .symbolSize(90)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                            .foregroundStyle(palette.hairline.color)
                        AxisValueLabel {
                            if let price = value.as(Double.self) {
                                Text(compactPriceText(price))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                            .foregroundStyle(palette.hairline.color.opacity(0.55))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(valueScrubGesture(proxy: proxy, geometry: geometry, points: points))
                            .simultaneousGesture(valueShareLongPressGesture)
                    }
                }
            }
            .frame(height: 150)
            .animation(.easeOut(duration: 0.12), value: scrubbedValuePoint?.id)
            .onDisappear { scrubbedValuePoint = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("card-value-history-chart")
            .accessibilityLabel("90-day value chart")
            .accessibilityValue(accessibilitySummary)
            // The long-press share is gesture-only, so expose it to VoiceOver (which
            // can't scrub the chart) as an accessibility action on the latest point.
            .accessibilityAction(named: Text("Share Latest Price")) {
                if let point = points.last {
                    valueHistoryShareItem = PriceHistoryShareItem(
                        text: snapshotText(point)
                    )
                }
            }
            .sheet(item: $valueHistoryShareItem) { valueHistoryShareSheet($0) }
        } else {
            Text("No 90-day chart is available for this printing.")
                .font(.callout)
                .foregroundStyle(palette.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("card-value-chart-unavailable")
        }
    }

    // Computed only when read (inside the chart-present branch), from this
    // view's own points — no work on the no-data path.
    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else {
            return "No chart data"
        }
        return "From \(dateText(first.date)) at \(priceText(first.price)) to \(dateText(last.date)) at \(priceText(last.price))"
    }

    // Drag anywhere over the plot to read the value on that day; release snaps
    // the readout away. Works with mouse drags on macOS and touch elsewhere.
    private func valueScrubGesture(
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [CardValueChartPoint]
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                updateScrub(at: value.location, proxy: proxy, geometry: geometry, points: points)
            }
            .onEnded { _ in
                if scrubbedValuePoint != nil {
                    scrubbedValuePoint = nil
                }
            }
    }

    private func updateScrub(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [CardValueChartPoint]
    ) {
        guard let plotFrame = proxy.plotFrame else {
            return
        }
        let xPosition = location.x - geometry[plotFrame].origin.x
        guard let date = proxy.value(atX: xPosition, as: Date.self),
              let nearest = nearestChartPoint(to: date, in: points)
        else {
            return
        }
        if scrubbedValuePoint?.id != nearest.id {
            scrubbedValuePoint = nearest
            detailFeedbackTrigger += 1
        }
    }

    private func scrubReadout(for point: CardValueChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateText(point.date))
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
            Text(priceText(point.price))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(palette.cardSurface.color)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .shadow(color: palette.shadow.color.opacity(0.25), radius: 4, x: 0, y: 2)
        .fixedSize()
        .accessibilityHidden(true)
    }

    // A long press while scrubbing freezes the held point and offers a text
    // snapshot to share. It runs simultaneously with the scrub drag, so the
    // point under the finger is still set when the press completes.
    private var valueShareLongPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                guard let point = scrubbedValuePoint else {
                    return
                }
                valueHistoryShareItem = PriceHistoryShareItem(
                    text: snapshotText(point)
                )
                shareFeedbackTrigger += 1
            }
    }

    private func valueHistoryShareSheet(_ item: PriceHistoryShareItem) -> some View {
        VStack(spacing: 18) {
            Text(item.text)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.primaryText.color)

            ShareLink(item: item.text) {
                Label("Share Snapshot", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .accessibilityIdentifier("card-value-history-share")
        #if os(iOS) || os(visionOS)
        .presentationDetents([.height(170)])
        #endif
    }
}

private struct PriceHistoryShareItem: Identifiable {
    let id = UUID()
    let text: String
}
