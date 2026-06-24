import GrimoraCore
import SwiftUI

struct CardRefinementButton: View {
    @Environment(GrimoraAppModel.self) private var model

    var groups: [SearchRefinementGroup]

    @State private var isPresented = false
    @State private var presentationID = 0

    var body: some View {
        Button("Refine", systemImage: "checklist", action: present)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("card-detail-refine-button")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                SearchRefinementPanel(
                    groups: groups,
                    currentQuery: currentQuery,
                    onApply: apply,
                    onCancel: dismiss
                )
                .id(presentationID)
                .presentationCompactAdaptation(.sheet)
            }
    }

    private var currentQuery: String {
        model.submittedSearchText
    }

    private func present() {
        presentationID += 1
        isPresented = true
    }

    private func apply(_ updates: [SearchRefinementUpdate]) {
        model.applySearchRefinements(updates)
        dismiss()
    }

    private func dismiss() {
        isPresented = false
    }
}
