import SwiftUI

struct GrimoraMenuSelectionLabel: View {
    var title: String
    var isSelected: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
