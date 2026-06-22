import GrimoraCore
import SwiftUI

/// Wraps the platform `SelectableOracleText` representable and pins it to the
/// width of the surrounding stack. The underlying text view sizes itself from
/// the width SwiftUI proposes; in the card detail inspector that proposal can
/// come through wider than the visible column, so the text lays out past the
/// trailing edge that the sibling sections respect and the last word of each
/// line gets clipped. Measuring the slot and feeding an explicit width back to
/// the representable keeps it inside the same container as everything else.
struct CardOracleText: View {
    var text: String
    var color: GrimoraColorValue
    var onIncludeSelection: (String) -> Void
    var onExcludeSelection: (String) -> Void

    @State private var resolvedWidth: CGFloat?

    var body: some View {
        SelectableOracleText(
            text: text,
            color: color,
            onIncludeSelection: onIncludeSelection,
            onExcludeSelection: onExcludeSelection
        )
        .frame(width: resolvedWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, newValue in
                        resolvedWidth = newValue
                    }
            }
        }
    }
}
