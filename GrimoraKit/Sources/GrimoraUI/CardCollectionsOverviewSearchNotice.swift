import SwiftUI

/// Inline notice shown above the dashboard grid when a cross-list search term
/// can't be applied (e.g. unsupported syntax).
struct CardCollectionsOverviewSearchNotice: View {
    var message: String
    var palette: GrimoraPalette

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(palette.secondaryText.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard-search-unsupported")
    }
}
