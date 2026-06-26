import SwiftUI

/// Title + subtitle heading for the card list import/create panel.
struct CardCollectionImportHeader: View {
    var title: String
    var subtitle: String
    var headerFont: Font
    var titleAccessibilityIdentifier: String?
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(headerFont)
                .foregroundStyle(palette.primaryText.color)
                .accessibilityIdentifier(titleAccessibilityIdentifier ?? "list-import-title")

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
