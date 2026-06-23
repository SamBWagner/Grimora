import GrimoraCore
import SwiftUI

/// "Card" group of the advanced-search form: the name, type-line, and rules-text
/// fields, each with its own include/exclude affordance.
struct AdvancedSearchCardSection: View {
    @Binding var name: AdvancedSearchTextCriterion
    @Binding var typeLine: AdvancedSearchTextCriterion
    @Binding var oracleText: AdvancedSearchTextCriterion

    var body: some View {
        Section("Card") {
            AdvancedSearchTextRow(
                title: "Name",
                prompt: "Lightning Bolt",
                criterion: $name,
                identifier: "name"
            )
            AdvancedSearchTextRow(
                title: "Type Line",
                prompt: "Legendary Creature",
                criterion: $typeLine,
                identifier: "type"
            )
            AdvancedSearchTextRow(
                title: "Rules Text",
                prompt: "draw a card",
                criterion: $oracleText,
                identifier: "oracle"
            )
        }
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
