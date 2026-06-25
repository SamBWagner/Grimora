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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AdvancedSearchRarity.allCases) { rarity in
                Toggle(rarity.displayName, isOn: selection(rarity))
                    .toggleStyle(
                        RarityToggleStyle(
                            fill: rarity.fillColor(for: colorScheme),
                            selectedForeground: rarity.selectedForeground(for: colorScheme)
                        )
                    )
                    .accessibilityIdentifier("advanced-search-rarity-\(rarity.id)")
            }
        }
    }
}

/// A pill toggle tinted by Magic rarity colour. Selection is conveyed by filling
/// the pill (a shape change, not just hue) so it still reads with Differentiate
/// Without Color, while the rarity colour shows in both states.
private struct RarityToggleStyle: ToggleStyle {
    var fill: Color
    var selectedForeground: Color

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.subheadline)
                .foregroundStyle(isOn ? selectedForeground : fill)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    Capsule().fill(fill.opacity(isOn ? 1 : 0.14))
                }
                .overlay {
                    Capsule().strokeBorder(fill.opacity(isOn ? 0 : 0.45), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
