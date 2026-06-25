import GrimoraCore
import SwiftUI

/// "Stats" group of the advanced-search form: zero or more mana-value / power /
/// toughness comparisons, with add and per-row remove affordances.
struct AdvancedSearchStatsSection: View {
    @Binding var stats: [AdvancedSearchStatConstraint]
    var onAdd: () -> Void
    var onRemove: (AdvancedSearchStatConstraint) -> Void

    var body: some View {
        Section {
            ForEach($stats) { $stat in
                AdvancedSearchStatRow(stat: $stat) {
                    onRemove(stat)
                }
                #if os(iOS) || os(visionOS)
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onRemove(stat)
                    }
                    .accessibilityIdentifier("advanced-search-remove-stat")
                }
                #endif
            }

            Button("Add a stat filter", systemImage: "plus.circle", action: onAdd)
                .accessibilityIdentifier("advanced-search-add-stat")
        } header: {
            Text("Stats")
        } footer: {
            if stats.isEmpty {
                Text("Filter by mana value, power, or toughness — add as many comparisons as you like.")
            } else {
                Text("Swipe a row left to remove it.")
            }
        }
    }
}

// MARK: - Stat row

/// One mana-value / power / toughness comparison row, read as a phrase
/// ("Mana value · is · 3"). The comparison picker already covers negation
/// (`is not`), so there is no separate negate control. On touch platforms the
/// row is removed by swiping; macOS keeps an inline remove button.
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
            .fixedSize()
            .accessibilityIdentifier("advanced-search-stat-field")

            Picker("Comparison", selection: $stat.comparison) {
                ForEach(AdvancedSearchComparison.allCases) { comparison in
                    Text(comparison.displayName).tag(comparison)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("advanced-search-stat-comparison")

            Spacer(minLength: 8)

            TextField("Value", text: $stat.value, prompt: Text("3"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 64)
                #if os(iOS) || os(visionOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityIdentifier("advanced-search-stat-value")

            #if os(macOS)
            Button("Remove stat filter", systemImage: "minus.circle.fill", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityIdentifier("advanced-search-remove-stat")
            #endif
        }
    }
}
