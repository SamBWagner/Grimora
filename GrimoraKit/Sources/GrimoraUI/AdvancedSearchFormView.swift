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
            cardSection
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
            statsSection
            raritySection
            formatSection
        }
        .formStyle(.grouped)
        .grimoraSelectionFeedback(trigger: selectionTrigger)
        .accessibilityIdentifier("advanced-search-form")
    }

    // MARK: - Card text

    private var cardSection: some View {
        Section("Card") {
            AdvancedSearchTextRow(
                title: "Name",
                prompt: "Lightning Bolt",
                criterion: $builder.name,
                identifier: "name"
            )
            AdvancedSearchTextRow(
                title: "Type Line",
                prompt: "Legendary Creature",
                criterion: $builder.typeLine,
                identifier: "type"
            )
            AdvancedSearchTextRow(
                title: "Rules Text",
                prompt: "draw a card",
                criterion: $builder.oracleText,
                identifier: "oracle"
            )
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            ForEach($builder.stats) { $stat in
                AdvancedSearchStatRow(stat: $stat) {
                    removeStat(stat)
                }
            }

            Button("Add a stat filter", systemImage: "plus.circle", action: addStatRow)
                .accessibilityIdentifier("advanced-search-add-stat")
        } header: {
            Text("Stats")
        } footer: {
            if builder.stats.isEmpty {
                Text("Filter by mana value, power, or toughness — add as many comparisons as you like.")
            }
        }
    }

    // MARK: - Rarity

    private var raritySection: some View {
        Section("Rarity") {
            ViewThatFits(in: .horizontal) {
                rarityToggles
                ScrollView(.horizontal, showsIndicators: false) { rarityToggles }
            }
        }
    }

    private var rarityToggles: some View {
        HStack(spacing: 8) {
            ForEach(AdvancedSearchRarity.allCases) { rarity in
                Toggle(rarity.displayName, isOn: raritySelection(rarity))
                    .toggleStyle(.button)
                    .accessibilityIdentifier("advanced-search-rarity-\(rarity.id)")
            }
        }
    }

    // MARK: - Format

    private var formatSection: some View {
        Section("Format Legality") {
            Picker("Format", selection: $builder.format) {
                Text("Any").tag(AdvancedSearchFormat?.none)
                ForEach(AdvancedSearchFormat.allCases) { format in
                    Text(format.displayName).tag(AdvancedSearchFormat?.some(format))
                }
            }
            .accessibilityIdentifier("advanced-search-format-picker")

            if builder.format != nil {
                Picker("Status", selection: $builder.formatStatus) {
                    ForEach(AdvancedSearchFormatStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("advanced-search-format-status-picker")
            }
        }
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

// MARK: - Text row

/// A labelled text field. The include/exclude control only appears once the
/// field has a value, keeping empty rows clean.
private struct AdvancedSearchTextRow: View {
    var title: String
    var prompt: String
    @Binding var criterion: AdvancedSearchTextCriterion
    var identifier: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(title, text: $criterion.text, prompt: Text(prompt))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("advanced-search-\(identifier)-field")

                if !criterion.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    IncludeExcludeMenu(isNegated: $criterion.isNegated, identifier: identifier)
                }
            }
        }
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

// MARK: - Stat row

/// One mana-value / power / toughness comparison row. The comparison picker
/// already covers negation (`is not`), so there is no separate negate control.
private struct AdvancedSearchStatRow: View {
    @Binding var stat: AdvancedSearchStatConstraint
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Stat", selection: $stat.stat) {
                ForEach(AdvancedSearchStat.allCases) { stat in
                    Text(stat.displayName).tag(stat)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("advanced-search-stat-field")

            Picker("Comparison", selection: $stat.comparison) {
                ForEach(AdvancedSearchComparison.allCases) { comparison in
                    Text(comparison.displayName).tag(comparison)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("advanced-search-stat-comparison")

            TextField("Value", text: $stat.value, prompt: Text("3"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 72)
                #if os(iOS) || os(visionOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityIdentifier("advanced-search-stat-value")

            Button("Remove stat filter", systemImage: "minus.circle.fill", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityIdentifier("advanced-search-remove-stat")
        }
    }
}

// MARK: - Include / exclude control

/// A compact menu that flips a clause between include and exclude, reusing the
/// app's include/exclude language (green plus / red minus).
private struct IncludeExcludeMenu: View {
    @Binding var isNegated: Bool
    var identifier: String

    var body: some View {
        Picker("Match", selection: $isNegated) {
            Label("Include", systemImage: "plus.circle").tag(false)
            Label("Exclude", systemImage: "minus.circle").tag(true)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .tint(isNegated ? .red : .secondary)
        .accessibilityLabel("Include or exclude")
        .accessibilityValue(isNegated ? "Exclude" : "Include")
        .accessibilityIdentifier("advanced-search-\(identifier)-negate")
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
