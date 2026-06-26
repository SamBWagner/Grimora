import SwiftUI

/// Leading accessory for a card list text row: a selection indicator in
/// selection mode, otherwise a drag handle.
struct CardCollectionTextRowLeadingIcon: View {
    var showsSelectionIndicator: Bool
    var isSelectedInSelection: Bool
    var palette: GrimoraPalette
    var selectionAccessibilityIdentifier: String
    var isDragEnabled: Bool

    @ViewBuilder
    var body: some View {
        if showsSelectionIndicator || isSelectedInSelection {
            CardGridSelectionIndicator(
                isSelected: isSelectedInSelection,
                palette: palette,
                accessibilityIdentifier: selectionAccessibilityIdentifier
            )
            .frame(width: 30)
        } else {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondaryText.color.opacity(isDragEnabled ? 0.72 : 0.35))
                .frame(width: 30, height: 30)
                .help("Drag Card")
                .accessibilityHidden(true)
        }
    }
}
