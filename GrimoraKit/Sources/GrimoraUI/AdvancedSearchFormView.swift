import GrimoraCore
import SwiftUI

/// A verbose, grouped-form query builder mirroring scryfall.com/advanced:
/// labelled fields, colour pips, numeric ranges, plus "Add another" and
/// include/exclude affordances. It is a pure presentation layer bound to an
/// ``AdvancedSearchBuilder`` — emitting the Scryfall string, showing it live, and
/// applying it to a search is handled by the host (S7c).
public struct AdvancedSearchFormView: View {
    @Binding private var builder: AdvancedSearchBuilder
    @State private var selectionTrigger = 0

    public init(builder: Binding<AdvancedSearchBuilder>) {
        self._builder = builder
    }

    public var body: some View {
        Form {
            AdvancedSearchCardSection(
                name: $builder.name,
                typeLine: $builder.typeLine,
                oracleText: $builder.oracleText
            )
            AdvancedSearchColorSection(
                title: "Card Colours",
                criterion: $builder.colors,
                identifier: "colors",
                onChange: registerSelection
            )
            AdvancedSearchColorSection(
                title: "Colour Identity",
                criterion: $builder.colorIdentity,
                identifier: "identity",
                onChange: registerSelection
            )
            AdvancedSearchStatsSection(
                stats: $builder.stats,
                onAdd: addStatRow,
                onRemove: removeStat
            )
            AdvancedSearchRaritySection(selection: raritySelection)
            AdvancedSearchFormatSection(
                format: $builder.format,
                formatStatus: $builder.formatStatus
            )
        }
        .formStyle(.grouped)
        .grimoraSelectionFeedback(trigger: selectionTrigger)
        .accessibilityIdentifier("advanced-search-form")
    }

    // MARK: - Mutations

    private func addStatRow() {
        builder.addStat()
        registerSelection()
    }

    private func raritySelection(_ rarity: AdvancedSearchRarity) -> Binding<Bool> {
        Binding(
            get: { builder.rarities.contains(rarity) },
            set: { isOn in
                if isOn {
                    builder.rarities.insert(rarity)
                } else {
                    builder.rarities.remove(rarity)
                }
                registerSelection()
            }
        )
    }

    private func removeStat(_ stat: AdvancedSearchStatConstraint) {
        builder.stats.removeAll { $0.id == stat.id }
        registerSelection()
    }

    private func registerSelection() {
        selectionTrigger += 1
    }
}

// MARK: - Colour section

/// A section of WUBRG colour pips. The match-mode picker and exclude switch are
/// revealed only once at least one colour is chosen.
private struct AdvancedSearchColorSection: View {
    var title: String
    @Binding var criterion: AdvancedSearchColorCriterion
    var identifier: String
    var onChange: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric private var pipSize: Double = 28

    var body: some View {
        Section(title) {
            HStack(spacing: 10) {
                ForEach(ScryfallColor.allCases) { color in
                    ColorPipToggle(
                        color: color,
                        isSelected: criterion.colors.contains(color),
                        palette: palette,
                        size: pipSize
                    ) {
                        toggle(color)
                    }
                }
            }

            if !criterion.colors.isEmpty {
                Picker("Match", selection: $criterion.match) {
                    ForEach(AdvancedSearchColorMatch.allCases) { match in
                        Text(match.displayName).tag(match)
                    }
                }
                .accessibilityIdentifier("advanced-search-\(identifier)-match-picker")

                Toggle("Exclude these colours", isOn: $criterion.isNegated)
                    .accessibilityIdentifier("advanced-search-\(identifier)-negate")
            }
        }
    }

    private func toggle(_ color: ScryfallColor) {
        if criterion.colors.contains(color) {
            criterion.colors.remove(color)
        } else {
            criterion.colors.insert(color)
        }
        onChange()
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

/// A single tappable mana-colour pip that reflects selection state.
private struct ColorPipToggle: View {
    var color: ScryfallColor
    var isSelected: Bool
    var palette: GrimoraPalette
    var size: Double
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ManaSymbolView(
                symbol: ManaCostSymbol(rawValue: color.symbol),
                palette: palette,
                size: size
            )
            .opacity(isSelected ? 1 : 0.3)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(palette.accent.color, lineWidth: 2)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("advanced-search-color-\(color.symbol)")
    }
}

#if DEBUG
private struct AdvancedSearchFormPreview: View {
    @State private var builder = AdvancedSearchBuilder()

    var body: some View {
        VStack(spacing: 0) {
            AdvancedSearchFormView(builder: $builder)
            Divider()
            Text(builder.scryfallQuery.isEmpty ? "—" : builder.scryfallQuery)
                .font(.footnote.monospaced())
                .padding()
        }
    }
}

#Preview {
    AdvancedSearchFormPreview()
}
#endif
