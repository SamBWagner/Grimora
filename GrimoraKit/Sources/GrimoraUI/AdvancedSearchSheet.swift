import GrimoraCore
import SwiftUI

/// Hosts ``AdvancedSearchFormView`` in a sheet, showing the Scryfall query it
/// generates live (so people learn the syntax) and running it through the normal
/// submit path when they tap Search.
struct AdvancedSearchSheet: View {
    @Binding var builder: AdvancedSearchBuilder
    var onApply: (AdvancedSearchBuilder) -> Void
    /// Called when Reset is tapped, after the form is emptied, so the host can
    /// also clear the live (committed) search instead of leaving stale results.
    var onReset: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Compile the query once per render and thread it through the bar and the
        // toolbar, instead of recomputing `scryfallQuery`/`isEmpty` several times.
        let query = builder.scryfallQuery
        return NavigationStack {
            AdvancedSearchFormView(builder: $builder)
                .safeAreaInset(edge: .bottom) {
                    AdvancedSearchGeneratedQueryBar(
                        query: query,
                        palette: palette,
                        onReset: reset
                    )
                    .equatable()
                }
                .navigationTitle("Advanced Search")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent(isEmpty: query.isEmpty) }
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(isEmpty: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done", action: dismiss.callAsFunction)
                .accessibilityIdentifier("advanced-search-done")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Search", action: apply)
                .disabled(isEmpty)
                .accessibilityIdentifier("advanced-search-submit")
        }
    }

    private func apply() {
        onApply(builder)
        dismiss()
    }

    private func reset() {
        builder.reset()
        onReset()
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
