import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Width at which the card detail pane shows the card artwork as large as it
/// usefully gets: the art fills the pane's visible *height*, bounded so it never
/// upscales past the source image (`nativeCardWidth`) and never starves the
/// sidebar + search grid (`reservedLeadingWidth`). Driving the width off height
/// — not the pane's own width — is what keeps the resizable pane layout-loop-safe.
///
/// Pure + side-effect free so it can be unit-tested without rendering, mirroring
/// `compactPrintingDotWindow`.
func cardDetailMaximizedPaneWidth(
    paneHeight: CGFloat,
    windowWidth: CGFloat,
    minWidth: CGFloat,
    nativeCardWidth: CGFloat,
    reservedLeadingWidth: CGFloat,
    horizontalInsets: CGFloat,
    verticalInsets: CGFloat,
    aspectRatio: CGFloat = cardArtworkAspectRatio
) -> CGFloat {
    guard paneHeight.isFinite, windowWidth.isFinite, aspectRatio > 0 else {
        return minWidth
    }

    let cardMaxHeight = max(0, paneHeight - verticalInsets)
    let fromHeight = cardMaxHeight * aspectRatio + horizontalInsets
    let nativeCap = nativeCardWidth + horizontalInsets
    let windowCap = windowWidth - reservedLeadingWidth

    return max(minWidth, min(fromHeight, nativeCap, windowCap))
}

/// Lets `CardDetailView` tell the surrounding resizable column the minimum width
/// its current content needs (e.g. the wide "Show All" expanded printings
/// browser). The column grows to honour it; the value is mode-constant — it never
/// depends on the pane's actual width — so feeding it back into the frame can't
/// form a layout loop.
struct CardDetailContentMinWidthKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

#if os(macOS)
/// The draggable border between the search grid and the card detail pane.
/// Dragging resizes the pane (clamped); double-clicking toggles the pane to the
/// "fit the card" width and back — the Excel-style fit-to-content gesture.
struct CardDetailPaneDivider: View {
    var currentWidth: CGFloat
    var minWidth: CGFloat
    var maxWidth: CGFloat
    var onResize: (CGFloat) -> Void
    var onToggleMaximized: () -> Void

    @State private var dragBaseWidth: CGFloat?

    private static let hitWidth: CGFloat = 10

    var body: some View {
        // The whole `hitWidth`-wide column is the hit target (a centred 1pt line is
        // the only thing drawn). Keeping the hit area inside the view's own bounds
        // — rather than an overlay that spills past a 1pt parent — is what makes the
        // drag + double-click reliably register.
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .frame(width: Self.hitWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(dragGesture)
        .onTapGesture(count: 2) { onToggleMaximized() }
        .accessibilityIdentifier("card-detail-pane-divider")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = dragBaseWidth ?? currentWidth
                if dragBaseWidth == nil {
                    dragBaseWidth = base
                }
                // The divider sits on the pane's leading edge, so dragging left
                // (negative translation) widens the pane.
                let proposed = base - value.translation.width
                onResize(min(max(proposed, minWidth), maxWidth))
            }
            .onEnded { _ in
                dragBaseWidth = nil
            }
    }
}
#endif
