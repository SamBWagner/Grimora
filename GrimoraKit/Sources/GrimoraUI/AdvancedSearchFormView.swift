import GrimoraCore
import SwiftUI

/// A verbose, form-based query builder mirroring scryfall.com/advanced: toggles,
/// pickers, numeric ranges, plus "Add another" and "Negate" affordances. It is a
/// pure presentation layer bound to an ``AdvancedSearchBuilder`` — emitting the
/// Scryfall string, showing it live, and applying it to a search is handled by
/// the host (S7c).
public struct AdvancedSearchFormView: View {
    @Binding private var builder: AdvancedSearchBuilder
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectionTrigger = 0

    public init(builder: Binding<AdvancedSearchBuilder>) {
        self._builder = builder
    }

    public var body: some View {
        Form {
            cardTextSection
            coloursSection
            statsSection
            raritySection
            formatSection
        }
        .grimoraSelectionFeedback(trigger: selectionTrigger)
        .accessibilityIdentifier("advanced-search-form")
    }

    // MARK: - Card text

    private var cardTextSection: some View {
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

    // MARK: - Colours

    private var coloursSection: some View {
        Section("Colours") {
            AdvancedSearchColorRow(
                title: "Card colours",
                criterion: $builder.colors,
                identifier: "colors",
                onChange: registerSelection
            )
            AdvancedSearchColorRow(
                title: "Colour identity",
                criterion: $builder.colorIdentity,
                identifier: "identity",
                onChange: registerSelection
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

            Button("Add another stat", systemImage: "plus.circle", action: addStatRow)
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
            MultiSelectChipRow(
                items: AdvancedSearchRarity.allCases,
                isSelected: { builder.rarities.contains($0) },
                label: \.displayName,
                identifierPrefix: "rarity"
            ) { rarity in
                toggle(rarity)
            }
        }
    }

    // MARK: - Format

    private var formatSection: some View {
        Section("Format legality") {
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

    private func toggle(_ rarity: AdvancedSearchRarity) {
        if builder.rarities.contains(rarity) {
            builder.rarities.remove(rarity)
        } else {
            builder.rarities.insert(rarity)
        }
        registerSelection()
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

/// A labelled text field with a trailing negate toggle.
private struct AdvancedSearchTextRow: View {
    var title: String
    var prompt: String
    @Binding var criterion: AdvancedSearchTextCriterion
    var identifier: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(title, text: $criterion.text, prompt: Text(prompt))
                .accessibilityIdentifier("advanced-search-\(identifier)-field")
            NegateToggle(isNegated: $criterion.isNegated, identifier: identifier)
        }
    }
}

// MARK: - Colour row

/// A row of WUBRG colour pips with a match-mode picker and a negate toggle.
private struct AdvancedSearchColorRow: View {
    var title: String
    @Binding var criterion: AdvancedSearchColorCriterion
    var identifier: String
    var onChange: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric private var pipSize: Double = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                NegateToggle(isNegated: $criterion.isNegated, identifier: identifier)
            }

            HStack(spacing: 8) {
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

            Picker("Match", selection: $criterion.match) {
                ForEach(AdvancedSearchColorMatch.allCases) { match in
                    Text(match.displayName).tag(match)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("advanced-search-\(identifier)-match-picker")
        }
        .padding(.vertical, 2)
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

/// One mana-value / power / toughness comparison row with a negate toggle and a
/// remove button.
private struct AdvancedSearchStatRow: View {
    @Binding var stat: AdvancedSearchStatConstraint
    var onRemove: () -> Void

    var body: some View {
        VStack(spacing: 8) {
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

                valueField
            }

            HStack {
                NegateToggle(isNegated: $stat.isNegated, identifier: "stat")
                Spacer()
                Button("Remove stat filter", systemImage: "minus.circle", role: .destructive, action: onRemove)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("advanced-search-remove-stat")
            }
        }
        .padding(.vertical, 2)
    }

    private var valueField: some View {
        TextField("Value", text: $stat.value, prompt: Text("3"))
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 80)
            #if os(iOS) || os(visionOS)
            .keyboardType(.numbersAndPunctuation)
            #endif
            .accessibilityIdentifier("advanced-search-stat-value")
    }
}

// MARK: - Shared controls

/// A compact button toggle that flips a clause's negation, tinting red when on.
private struct NegateToggle: View {
    @Binding var isNegated: Bool
    var identifier: String

    var body: some View {
        Toggle(isOn: $isNegated) {
            Label("Negate", systemImage: isNegated ? "exclamationmark.circle.fill" : "exclamationmark.circle")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .tint(.red)
        .accessibilityLabel("Negate")
        .accessibilityValue(isNegated ? "On" : "Off")
        .accessibilityIdentifier("advanced-search-\(identifier)-negate")
    }
}

/// A horizontal row of multi-select choice chips (used for rarity), scrolling
/// only if the chips cannot all fit at the current Dynamic Type size.
private struct MultiSelectChipRow<Item: Hashable & Identifiable>: View {
    var items: [Item]
    var isSelected: (Item) -> Bool
    var label: (Item) -> String
    var identifierPrefix: String
    var action: (Item) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                let selected = isSelected(item)
                Button {
                    action(item)
                } label: {
                    Text(label(item))
                        .font(.callout)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(selected ? .accentColor : .secondary)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("advanced-search-\(identifierPrefix)-\(item.id)")
            }
        }
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
