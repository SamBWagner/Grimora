import GrimoraCore
import SwiftUI

struct SearchRefinementPanel: View {
    var groups: [SearchRefinementGroup]
    var currentQuery: String
    var onApply: ([SearchRefinementUpdate]) -> Void
    var onCancel: () -> Void

    @State private var states: [SearchRefinement.ID: SearchRefinementState]

    init(
        groups: [SearchRefinementGroup],
        currentQuery: String,
        onApply: @escaping ([SearchRefinementUpdate]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groups = groups
        self.currentQuery = currentQuery
        self.onApply = onApply
        self.onCancel = onCancel
        let refinements = groups.flatMap(\.refinements)
        _states = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: refinements.map {
                    ($0.id, SearchQuery.state(for: $0, in: currentQuery))
                }
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Refine Search")
                .font(.headline)

            Text("Click a trait to cycle between include, exclude, and neutral.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(group.refinements) { refinement in
                                SearchRefinementRow(
                                    refinement: refinement,
                                    state: states[refinement.id] ?? .neutral,
                                    onCycle: { cycle(refinement) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 360)

            Divider()

            HStack {
                Button("Clear", action: clear)
                    .accessibilityIdentifier("search-refinement-clear")

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                    .accessibilityIdentifier("search-refinement-cancel")

                Button("Apply", action: apply)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("search-refinement-apply")
            }
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 340)
        .accessibilityIdentifier("search-refinement-panel")
    }

    private func cycle(_ refinement: SearchRefinement) {
        states[refinement.id] = (states[refinement.id] ?? .neutral).next
    }

    private func clear() {
        for refinement in groups.flatMap(\.refinements) {
            states[refinement.id] = .neutral
        }
    }

    private func apply() {
        onApply(
            groups.flatMap(\.refinements).map {
                SearchRefinementUpdate(
                    refinement: $0,
                    state: states[$0.id] ?? .neutral
                )
            }
        )
    }
}
