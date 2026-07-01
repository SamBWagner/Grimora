import GrimoraCore
import SwiftUI

/// A small capsule chip naming a card's foil treatment (e.g. "Foil", "Etched", "Halo Foil").
/// Mirrors the finish chips MTG Mate shows in its list rows. Renders nothing for `.none`.
struct FoilTreatmentBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var treatment: CardFoilTreatment

    @ViewBuilder
    var body: some View {
        if treatment != .none {
            Text(treatment.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(palette.hairline.color, lineWidth: 1)
                }
                .foregroundStyle(palette.primaryText.color)
                .accessibilityLabel("\(treatment.displayName) finish")
        }
    }

    private var palette: GrimoraPalette {
        .cached(for: colorScheme)
    }
}
