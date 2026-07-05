import SwiftUI

/// Dashboard header: the "Collections" title with a live count and the "New Collection"
/// action. Owns the selection-feedback trigger for its create button.
///
/// The title/count and the create action share one row when they both fit. On a narrow
/// phone — or at large Dynamic Type — that row can't hold them without the button label
/// wrapping onto two lines, so a `ViewThatFits` fallback drops the button onto its own
/// row beneath the title instead. The label also carries `.lineLimit(1)`/`.fixedSize` so
/// it never wraps even in the single-row arrangement.
struct CardCollectionsOverviewHeader: View {
    var countText: String
    var palette: GrimoraPalette
    var onCreateList: () -> Void

    @State private var createListFeedbackTrigger = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            headerLayout(stacked: false)
            headerLayout(stacked: true)
        }
    }

    @ViewBuilder
    private func headerLayout(stacked: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                createButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 12) {
                titleBlock
                Spacer(minLength: 0)
                createButton
            }
        }
    }

    private var titleBlock: some View {
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
    }

    private var createButton: some View {
        Button {
            createListFeedbackTrigger += 1
            onCreateList()
        } label: {
            Label("New Collection", systemImage: "plus")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("create-list-button")
        .grimoraSelectionFeedback(trigger: createListFeedbackTrigger)
    }
}
