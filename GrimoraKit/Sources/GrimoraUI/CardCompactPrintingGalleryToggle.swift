import SwiftUI

/// The circular toggle overlaid on the compact printings gallery that switches
/// between the single-printing pager and the all-printings grid.
struct CardCompactPrintingGalleryToggle: View {
    @Binding var isShowingAllPrintings: Bool
    @Binding var detailFeedbackTrigger: Int
    var palette: GrimoraPalette

    var body: some View {
        Button {
            detailFeedbackTrigger += 1
            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingAllPrintings.toggle()
            }
        } label: {
            Label(
                isShowingAllPrintings ? "Show selected printing" : "Show all printings",
                systemImage: isShowingAllPrintings ? "rectangle.portrait" : "square.grid.2x2"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .font(.headline.weight(.semibold))
        .foregroundStyle(palette.primaryText.color)
        .frame(width: 36, height: 36)
        .background(palette.cardSurface.color.opacity(0.92))
        .clipShape(Circle())
        .shadow(color: palette.shadow.color.opacity(0.35), radius: 5, x: 0, y: 3)
        .accessibilityIdentifier("card-printings-show-all-button")
        .accessibilityValue(isShowingAllPrintings ? "Expanded" : "Collapsed")
    }
}
