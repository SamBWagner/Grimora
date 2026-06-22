#if os(macOS)
import GrimoraCore
import SwiftUI
import AppKit

struct NativeMacSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var focusRequestID: Int
    var placeholder: String
    var identifier: String = "mac-inline-search-field"
    var recentSearches: [String]
    var onClearRecentSearches: () -> Void
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusReportingSearchField(frame: .zero)
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldAction(_:))
        field.onInteraction = { [weak coordinator = context.coordinator] in
            coordinator?.focusFromInteraction()
        }
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        field.maximumRecents = GrimoraSearchHistoryStore.maxQueryCount
        field.recentSearches = recentSearches
        field.searchMenuTemplate = context.coordinator.searchMenuTemplate()
        Self.configureSearchField(field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if let field = field as? FocusReportingSearchField {
            field.onInteraction = { [weak coordinator = context.coordinator] in
                coordinator?.focusFromInteraction()
            }
        }
        if field.stringValue != text,
           !context.coordinator.isEditing {
            field.stringValue = text
            context.coordinator.lastEditedText = text
        }
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.placeholderString = placeholder
        field.recentSearches = recentSearches
        field.searchMenuTemplate = context.coordinator.searchMenuTemplate()
        Self.configureSearchField(field)
        context.coordinator.refreshSyntaxHighlighting(in: field, allowsHaptics: false)

        guard isFocused else {
            return
        }

        let shouldApplyFocus =
            context.coordinator.lastAppliedFocusRequestID != focusRequestID
            || field.currentEditor() == nil
        guard shouldApplyFocus else {
            return
        }

        context.coordinator.lastAppliedFocusRequestID = focusRequestID
        let coordinator = context.coordinator
        let requestID = focusRequestID
        DispatchQueue.main.async { [weak field, weak coordinator] in
            guard let field,
                  let coordinator,
                  coordinator.parent.isFocused,
                  coordinator.lastAppliedFocusRequestID == requestID
            else {
                return
            }

            field.window?.makeFirstResponder(field)
        }
    }

    private static func configureSearchField(_ field: NSSearchField) {
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.masksToBounds = true
        field.layer?.cornerCurve = .continuous
        field.layer?.cornerRadius = searchFieldCornerRadius(for: field.bounds)
        field.font = .systemFont(ofSize: 15, weight: .regular)
        field.controlSize = .large
    }

    private static func searchFieldCornerRadius(for bounds: CGRect) -> CGFloat {
        max(0, bounds.height / 2)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class FocusReportingSearchField: NSSearchField {
        var onInteraction: @MainActor () -> Void = {}

        override var focusRingType: NSFocusRingType {
            get { .none }
            set { super.focusRingType = .none }
        }

        override var focusRingMaskBounds: NSRect {
            .zero
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func drawFocusRingMask() {}

        override func layout() {
            super.layout()
            layer?.cornerRadius = NativeMacSearchField.searchFieldCornerRadius(for: bounds)
        }

        override func mouseDown(with event: NSEvent) {
            onInteraction()
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeMacSearchField
        var lastAppliedFocusRequestID = -1
        var isEditing = false
        var lastEditedText = ""
        private var lastInvalidClauseCount = 0

        init(parent: NativeMacSearchField) {
            self.parent = parent
        }

        /// Recolours each top-level clause of the query directly in the field and fires
        /// a light haptic when a clause newly turns red. Mutating the field editor's
        /// text storage in place preserves the insertion point while typing.
        @MainActor
        func refreshSyntaxHighlighting(in field: NSSearchField, allowsHaptics: Bool) {
            let text = field.stringValue
            let segments = ScryfallSyntaxHighlighter.segments(for: text)
            applyHighlightColors(segments: segments, text: text, to: field)

            let invalidCount = segments.reduce(into: 0) { count, segment in
                if segment.highlight == .invalid {
                    count += 1
                }
            }
            if allowsHaptics, invalidCount > lastInvalidClauseCount {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .now
                )
            }
            lastInvalidClauseCount = invalidCount
        }

        @MainActor
        private func applyHighlightColors(
            segments: [ScryfallHighlightSegment],
            text: String,
            to field: NSSearchField
        ) {
            let font = field.font ?? .systemFont(ofSize: 15, weight: .regular)

            if let editor = field.currentEditor() as? NSTextView,
               let storage = editor.textStorage {
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
                for segment in segments {
                    storage.addAttribute(
                        .foregroundColor,
                        value: Self.highlightColor(for: segment.highlight),
                        range: NSRange(segment.range, in: text)
                    )
                }
                storage.endEditing()
                editor.typingAttributes[.foregroundColor] = NSColor.labelColor
                editor.typingAttributes[.font] = font
            } else {
                let attributed = NSMutableAttributedString(
                    string: text,
                    attributes: [.foregroundColor: NSColor.labelColor, .font: font]
                )
                for segment in segments {
                    attributed.addAttribute(
                        .foregroundColor,
                        value: Self.highlightColor(for: segment.highlight),
                        range: NSRange(segment.range, in: text)
                    )
                }
                field.attributedStringValue = attributed
            }
        }

        private static func highlightColor(for highlight: ScryfallClauseHighlight) -> NSColor {
            switch highlight {
            case .pending:
                .labelColor
            case .valid:
                .systemGreen
            case .invalid:
                .systemRed
            case .incomplete:
                .systemYellow
            }
        }

        func searchMenuTemplate() -> NSMenu {
            let menu = NSMenu()

            let clearRecents = NSMenuItem(
                title: "Clear Recent Searches",
                action: #selector(clearRecentSearches(_:)),
                keyEquivalent: ""
            )
            clearRecents.target = self
            clearRecents.tag = NSSearchField.clearRecentsMenuItemTag
            menu.addItem(clearRecents)

            let separator = NSMenuItem.separator()
            menu.addItem(separator)

            let recentsTitle = NSMenuItem(title: "Recent Searches", action: nil, keyEquivalent: "")
            recentsTitle.isEnabled = false
            recentsTitle.tag = NSSearchField.recentsTitleMenuItemTag
            menu.addItem(recentsTitle)

            let recents = NSMenuItem(title: "Recent Searches", action: nil, keyEquivalent: "")
            recents.tag = NSSearchField.recentsMenuItemTag
            menu.addItem(recents)

            let noRecents = NSMenuItem(title: "No Recent Searches", action: nil, keyEquivalent: "")
            noRecents.isEnabled = false
            noRecents.tag = NSSearchField.noRecentsMenuItemTag
            menu.addItem(noRecents)

            return menu
        }

        @MainActor
        @objc func clearRecentSearches(_ sender: NSMenuItem) {
            parent.onClearRecentSearches()
        }

        @MainActor
        @objc func selectRecentSearch(_ sender: NSMenuItem) {
            guard let query = sender.representedObject as? String else {
                return
            }
            parent.isFocused = true
            isEditing = true
            lastEditedText = query
            parent.text = query
        }

        @MainActor
        func focusFromInteraction() {
            isEditing = true
            parent.isFocused = true
        }

        @MainActor
        @objc func searchFieldAction(_ sender: NSSearchField) {
            parent.isFocused = true
            isEditing = true
            lastEditedText = sender.stringValue
            parent.text = sender.stringValue
            guard Self.isSubmitEvent(NSApp.currentEvent) else {
                return
            }
            parent.onSubmit()
        }

        private static func isSubmitEvent(_ event: NSEvent?) -> Bool {
            guard let event, event.type == .keyDown else {
                return false
            }
            // NSSearchField also sends its action when the built-in clear control is used.
            // Restrict submission to Return (36) and keypad Enter (76).
            return event.keyCode == 36 || event.keyCode == 76
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }

            parent.isFocused = true
            isEditing = true
            lastEditedText = field.stringValue
            parent.text = field.stringValue
            refreshSyntaxHighlighting(in: field, allowsHaptics: true)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            // Dismissal is owned by SearchFocusDismissalBridge so AppKit
            // responder churn during header transitions does not collapse the
            // active search surface before the replacement field can focus.
        }
    }
}
#endif
