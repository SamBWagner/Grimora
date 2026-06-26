import GrimoraCore
import SwiftUI

/// Wraps the platform `SelectableOracleText` representable so it wraps to the
/// width of the surrounding stack instead of laying the oracle text out as one
/// long line. The underlying text view reports its full single-line intrinsic
/// width when SwiftUI proposes an unspecified width during layout negotiation;
/// left unchecked that stretched the whole card-detail column past its
/// container (most visibly on the iPad fly-up sheet, where the start of each
/// line was clipped off the leading edge). `fixedSize(horizontal: false,
/// vertical: true)` makes it accept the proposed width and grow only
/// vertically — the same contract a plain `Text` honours — so it stays inside
/// the same bounds as the sibling sections.
struct CardOracleText: View {
    var text: String
    var color: GrimoraColorValue
    var onIncludeSelection: (String) -> Void
    var onExcludeSelection: (String) -> Void

    var body: some View {
        SelectableOracleText(
            text: text,
            color: color,
            onIncludeSelection: onIncludeSelection,
            onExcludeSelection: onExcludeSelection
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
