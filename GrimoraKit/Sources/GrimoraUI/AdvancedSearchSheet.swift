import GrimoraCore
import SwiftUI

/// Hosts ``AdvancedSearchFormView`` in a sheet, showing the Scryfall query it
/// generates live (so people learn the syntax) and running it through the normal
/// submit path when they tap Search.
struct AdvancedSearchSheet: View {
    @Binding var builder: AdvancedSearchBuilder
    var onApply: (AdvancedSearchBuilder) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            AdvancedSearchFormView(builder: $builder)
                .safeAreaInset(edge: .bottom) {
                    generatedQueryBar
                }
                .navigationTitle("Advanced Search")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done", action: dismiss.callAsFunction)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Search", action: apply)
                .disabled(builder.isEmpty)
        }
    }

    private var generatedQueryBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scryfall query")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(builder.scryfallQuery.isEmpty ? "—" : builder.scryfallQuery)
                    .font(.callout.monospaced())
                    .foregroundStyle(palette.syntaxValid.color)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .accessibilityIdentifier("advanced-search-generated-query")
            }
            Spacer(minLength: 0)
            Button("Reset", role: .destructive, action: reset)
                .buttonStyle(.borderless)
                .disabled(builder.isEmpty)
                .accessibilityIdentifier("advanced-search-reset")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generated Scryfall query")
        .accessibilityValue(builder.scryfallQuery.isEmpty ? "Empty" : builder.scryfallQuery)
    }

    private func apply() {
        onApply(builder)
        dismiss()
    }

    private func reset() {
        builder.reset()
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

/// The persistent on-screen affordance that opens the advanced-search builder.
struct AdvancedSearchLaunchButton: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric private var diameter: Double = 52

    var body: some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(palette.accent.color)
                .frame(width: diameter, height: diameter)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(palette.hairline.color, lineWidth: 1)
                }
                .shadow(color: palette.shadow.color.opacity(0.18), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advanced Search")
        .accessibilityHint("Build a Scryfall query with toggles and pickers")
        .accessibilityIdentifier("advanced-search-launch-button")
        .help("Advanced Search")
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

#if DEBUG
#Preview {
    struct Host: View {
        @State private var builder = AdvancedSearchBuilder()
        var body: some View {
            AdvancedSearchSheet(builder: $builder) { _ in }
        }
    }
    return Host()
}
#endif
