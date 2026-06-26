import SwiftUI

/// Dashboard header: the "Lists" title with a live count and the "New List"
/// action. Owns the selection-feedback trigger for its create button.
struct CardCollectionsOverviewHeader: View {
    var countText: String
    var palette: GrimoraPalette
    var onCreateList: () -> Void

    @State private var createListFeedbackTrigger = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Collections")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(1)

                Text(countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
                    .accessibilityIdentifier("card-lists-overview-count")
            }

            Spacer(minLength: 0)

            Button {
                createListFeedbackTrigger += 1
                onCreateList()
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("create-list-button")
            .grimoraSelectionFeedback(trigger: createListFeedbackTrigger)
        }
    }
}
