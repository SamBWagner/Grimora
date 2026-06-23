import SwiftUI

/// Small uppercased caption heading shared by the card list dashboard sections.
struct CardListDashboardSectionTitle: View {
    let text: String
    var palette: GrimoraPalette

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(palette.secondaryText.color)
            .textCase(.uppercase)
    }
}
