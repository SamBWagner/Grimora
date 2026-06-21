#if os(macOS)
import AppKit
import GrimoraCore
import SwiftUI

@MainActor
final class OracleSelectionTextView: NSTextView {
    var onIncludeSelection: ((String) -> Void)?
    var onExcludeSelection: ((String) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.items
            .filter { $0.tag == 7_301 || $0.tag == 7_302 || $0.tag == 7_303 }
            .forEach(menu.removeItem)

        guard !normalizedSelection.isEmpty else {
            return menu
        }

        let separator = NSMenuItem.separator()
        separator.tag = 7_301
        menu.addItem(separator)

        let includeItem = NSMenuItem(
            title: "More cards with “\(normalizedSelection)”",
            action: #selector(includeSelection),
            keyEquivalent: ""
        )
        includeItem.target = self
        includeItem.tag = 7_302
        includeItem.identifier = NSUserInterfaceItemIdentifier("oracle-selection-more-cards")
        menu.addItem(includeItem)

        let excludeItem = NSMenuItem(
            title: "Exclude “\(normalizedSelection)”",
            action: #selector(excludeSelection),
            keyEquivalent: ""
        )
        excludeItem.target = self
        excludeItem.tag = 7_303
        excludeItem.identifier = NSUserInterfaceItemIdentifier("oracle-selection-exclude")
        menu.addItem(excludeItem)
        return menu
    }

    @objc private func includeSelection() {
        guard !normalizedSelection.isEmpty else {
            return
        }
        onIncludeSelection?(normalizedSelection)
    }

    @objc private func excludeSelection() {
        guard !normalizedSelection.isEmpty else {
            return
        }
        onExcludeSelection?(normalizedSelection)
    }

    private var normalizedSelection: String {
        let range = selectedRange()
        guard range.length > 0,
              range.location != NSNotFound,
              NSMaxRange(range) <= (string as NSString).length
        else {
            return ""
        }
        return SearchRefinement.normalizedSelectedText(
            (string as NSString).substring(with: range)
        )
    }
}

struct SelectableOracleText: NSViewRepresentable {
    var text: String
    var color: GrimoraColorValue
    var onIncludeSelection: (String) -> Void
    var onExcludeSelection: (String) -> Void

    func makeNSView(context: Context) -> OracleSelectionTextView {
        let textView = OracleSelectionTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.font = .grimoraBody
        textView.setAccessibilityIdentifier("card-detail-oracle-text")
        update(textView)
        return textView
    }

    func updateNSView(_ textView: OracleSelectionTextView, context: Context) {
        update(textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: OracleSelectionTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            return nil
        }
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height)
        let lineHeight = textView.font.map { layoutManager.defaultLineHeight(for: $0) } ?? 0
        return CGSize(width: width, height: max(height, lineHeight))
    }

    private func update(_ textView: OracleSelectionTextView) {
        if textView.string != text {
            textView.string = text
        }
        textView.textColor = NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.opacity
        )
        textView.onIncludeSelection = onIncludeSelection
        textView.onExcludeSelection = onExcludeSelection
    }
}
#endif
