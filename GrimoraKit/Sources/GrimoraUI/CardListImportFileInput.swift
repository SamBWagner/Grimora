import SwiftUI

/// File-source affordance for the card list import panel: an explanatory card
/// with a "Choose File..." button.
struct CardListImportFileInput: View {
    var fileTitle: String
    var fileSubtitle: String
    var palette: GrimoraPalette
    var onChooseFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.accent.color)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(fileTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.primaryText.color)

                    Text(fileSubtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onChooseFile) {
                Label("Choose File...", systemImage: "folder")
            }
            .accessibilityIdentifier("list-import-file-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.placeholderFill.color.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
    }
}
