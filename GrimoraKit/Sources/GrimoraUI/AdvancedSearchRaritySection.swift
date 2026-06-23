import GrimoraCore
import SwiftUI

/// "Rarity" group of the advanced-search form: a horizontally scrolling row of
/// rarity toggle buttons, collapsing to a scroll view when space is tight.
struct AdvancedSearchRaritySection: View {
    var selection: (AdvancedSearchRarity) -> Binding<Bool>

    var body: some View {
        Section("Rarity") {
            ViewThatFits(in: .horizontal) {
                AdvancedSearchRarityToggles(selection: selection)
                ScrollView(.horizontal, showsIndicators: false) {
                    AdvancedSearchRarityToggles(selection: selection)
                }
            }
        }
    }
}

/// The rarity toggle buttons themselves, factored out so `ViewThatFits` can size
/// the same content with and without a horizontal scroll view.
private struct AdvancedSearchRarityToggles: View {
    var selection: (AdvancedSearchRarity) -> Binding<Bool>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AdvancedSearchRarity.allCases) { rarity in
                Toggle(rarity.displayName, isOn: selection(rarity))
                    .toggleStyle(.button)
                    .accessibilityIdentifier("advanced-search-rarity-\(rarity.id)")
            }
        }
    }
}
