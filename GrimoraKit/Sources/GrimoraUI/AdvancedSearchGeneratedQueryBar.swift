import SwiftUI

/// The live Scryfall-query preview pinned to the bottom of the advanced-search
/// sheet. Extracted into its own equatable view (taking the already-computed
/// query string) so it only re-renders when the query actually changes — not on
/// every form keystroke or keyboard-presentation frame, which is what made the
/// first text-field tap stall.
struct AdvancedSearchGeneratedQueryBar: View, Equatable {
    var query: String
    var palette: GrimoraPalette
    var onReset: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query && lhs.palette == rhs.palette
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scryfall query")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? "—" : query)
                    .font(.callout.monospaced())
                    .foregroundStyle(palette.syntaxValid.color)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .accessibilityIdentifier("advanced-search-generated-query")
            }
            Spacer(minLength: 0)
            Button("Reset", role: .destructive, action: onReset)
                .buttonStyle(.borderless)
                .disabled(query.isEmpty)
                .accessibilityIdentifier("advanced-search-reset")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generated Scryfall query")
        .accessibilityValue(query.isEmpty ? "Empty" : query)
    }
}
