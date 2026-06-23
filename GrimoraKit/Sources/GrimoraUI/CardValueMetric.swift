import SwiftUI

/// A single labelled value figure (e.g. "Current", "90-Day High") in the card
/// detail value section. The caller supplies the already-formatted price string.
struct CardValueMetric: View {
    let title: String
    let valueText: String
    let identifier: String
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)

            Text(valueText)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
