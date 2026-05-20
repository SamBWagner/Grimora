import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)
@MainActor
private final class NotesShortcutTextView: NSTextView {
    var shortcutHandler: ((RichTextEditorShortcut) -> Bool)?

    override func keyDown(with event: NSEvent) {
        guard let shortcut = RichTextEditorShortcut(event: event),
              shortcutHandler?(shortcut) == true
        else {
            super.keyDown(with: event)
            return
        }
    }
}

private extension RichTextEditorShortcut {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<RichTextEditorShortcutModifier>()
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }

        guard let shortcut = RichTextEditorShortcutResolver.shortcut(
            input: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: modifiers
        ) else {
            return nil
        }
        self = shortcut
    }
}

struct NativeRichTextEditor: NSViewRepresentable {
    @Binding var rtfdData: Data?
    @Binding var plainText: String
    @Binding var command: RichTextEditorCommand?
    var onRequestLink: () -> Void
    var onRequestAttachment: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.7
        scrollView.maxMagnification = 1.8

        let textView = NotesShortcutTextView()
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = .grimoraBody
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.delegate = context.coordinator
        textView.shortcutHandler = { shortcut in
            context.coordinator.handle(shortcut, in: textView)
        }
        textView.textStorage?.setAttributedString(
            RichTextDocumentIO.attributedString(rtfdData: rtfdData, plainText: plainText)
        )

        context.coordinator.textView = textView
        context.coordinator.lastRTFDData = rtfdData
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if context.coordinator.lastRTFDData != rtfdData {
            textView.textStorage?.setAttributedString(
                RichTextDocumentIO.attributedString(rtfdData: rtfdData, plainText: plainText)
            )
            context.coordinator.lastRTFDData = rtfdData
        }

        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.action, to: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeRichTextEditor
        weak var textView: NSTextView?
        var lastRTFDData: Data?
        var lastCommandID: UUID?

        init(parent: NativeRichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            publish(textView)
        }

        @discardableResult
        func apply(_ action: RichTextEditorAction, to textView: NSTextView) -> Bool {
            switch action {
            case .title:
                applyFont(.systemFont(ofSize: 26, weight: .bold), to: textView, expandsEmptySelection: true)
            case .heading:
                applyFont(.systemFont(ofSize: 19, weight: .semibold), to: textView, expandsEmptySelection: true)
            case .subheading:
                applyFont(.systemFont(ofSize: 16, weight: .semibold), to: textView, expandsEmptySelection: true)
            case .body:
                applyFont(.grimoraBody, to: textView, expandsEmptySelection: true)
            case .monostyled:
                applyFont(.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular), to: textView, expandsEmptySelection: true)
            case .bold:
                applyFontTrait(.boldFontMask, to: textView)
            case .italic:
                applyFontTrait(.italicFontMask, to: textView)
            case .underline:
                toggleStyleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: textView)
            case .strikethrough:
                toggleStyleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: textView)
            case .highlight:
                toggleStyleAttribute(.backgroundColor, value: PlatformColor.systemYellow.withAlphaComponent(0.45), in: textView)
            case .bulletedList:
                applyLinePrefix(in: textView, style: .bulleted)
            case .dashedList:
                applyLinePrefix(in: textView, style: .dashed)
            case .numberedList:
                applyLinePrefix(in: textView, style: .numbered)
            case .checklist:
                applyLinePrefix(in: textView, style: .checklist)
            case .toggleChecklist:
                toggleChecklist(in: textView)
            case .quote:
                applyLinePrefix(in: textView, style: .quote)
            case .increaseFontSize:
                adjustFontSize(by: 1, in: textView)
            case .decreaseFontSize:
                adjustFontSize(by: -1, in: textView)
            case .indent:
                indentSelectedLines(in: textView)
            case .outdent:
                outdentSelectedLines(in: textView)
            case .moveLineUp:
                moveSelectedLines(in: textView, direction: .up)
            case .moveLineDown:
                moveSelectedLines(in: textView, direction: .down)
            case .continueListOrNewline:
                guard continueListOrNewline(in: textView) else {
                    return false
                }
            case .softReturn:
                insert("\n", in: textView)
            case .literalTab:
                insert("\t", in: textView)
            case .zoomIn:
                adjustZoom(by: 0.1, in: textView)
            case .zoomOut:
                adjustZoom(by: -0.1, in: textView)
            case .resetZoom:
                setZoom(1, in: textView)
            case .link(let url):
                applyLink(url, to: textView)
            case .image(let data, let filename, _):
                insertImage(data: data, filename: filename, into: textView)
            }
            publish(textView)
            return true
        }

        func handle(_ shortcut: RichTextEditorShortcut, in textView: NSTextView) -> Bool {
            switch shortcut {
            case .action(let action):
                return apply(action, to: textView)
            case .requestLink:
                parent.onRequestLink()
            case .requestAttachment:
                parent.onRequestAttachment()
            }
            return true
        }

        private func applyFont(
            _ font: NSFont,
            to textView: NSTextView,
            expandsEmptySelection: Bool = false
        ) {
            let range = effectiveRange(in: textView, expandsEmptySelection: expandsEmptySelection)
            if range.length == 0 {
                var attributes = textView.typingAttributes
                attributes[.font] = font
                textView.typingAttributes = attributes
            } else {
                textView.textStorage?.addAttribute(.font, value: font, range: range)
            }
        }

        private func applyFontTrait(_ trait: NSFontTraitMask, to textView: NSTextView) {
            let range = textView.selectedRange()
            let currentFont: NSFont
            if range.length > 0,
               let storage = textView.textStorage,
               range.location < storage.length,
               let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            {
                currentFont = font
            } else {
                currentFont = textView.typingAttributes[.font] as? NSFont ?? .grimoraBody
            }
            let fontManager = NSFontManager.shared
            let converted: NSFont
            if fontManager.traits(of: currentFont).contains(trait) {
                converted = fontManager.convert(currentFont, toNotHaveTrait: trait)
            } else {
                converted = fontManager.convert(currentFont, toHaveTrait: trait)
            }
            applyFont(converted, to: textView)
        }

        private func toggleStyleAttribute(
            _ key: NSAttributedString.Key,
            value: Any,
            in textView: NSTextView
        ) {
            let result = RichTextInlineStyleEditing.togglingAttribute(
                key,
                value: value,
                in: attributedSnapshot(from: textView),
                selectedRange: effectiveRange(in: textView, expandsEmptySelection: false),
                typingAttributes: textView.typingAttributes
            )
            if let attributes = result.typingAttributes {
                textView.typingAttributes = attributes
            }
            if let attributedString = result.attributedString {
                let selectedRange = textView.selectedRange()
                textView.textStorage?.setAttributedString(attributedString)
                textView.setSelectedRange(selectedRange)
            }
        }

        private func applyLinePrefix(in textView: NSTextView, style: LinePrefixStyle) {
            let result = RichTextLineEditing.applyLinePrefix(
                to: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange(),
                style: style,
                fallbackAttributes: textView.typingAttributes
            )
            apply(result, to: textView)
        }

        private func toggleChecklist(in textView: NSTextView) {
            let result = RichTextLineEditing.toggleChecklist(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange()
            )
            apply(result, to: textView)
        }

        private func indentSelectedLines(in textView: NSTextView) {
            let result = RichTextLineEditing.indentLines(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange(),
                fallbackAttributes: textView.typingAttributes
            )
            apply(result, to: textView)
        }

        private func outdentSelectedLines(in textView: NSTextView) {
            let result = RichTextLineEditing.outdentLines(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange()
            )
            apply(result, to: textView)
        }

        private func moveSelectedLines(in textView: NSTextView, direction: LineMoveDirection) {
            guard let result = RichTextLineEditing.moveLines(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange(),
                direction: direction
            ) else {
                return
            }
            apply(result, to: textView)
        }

        private func adjustFontSize(by delta: CGFloat, in textView: NSTextView) {
            guard let storage = textView.textStorage else {
                return
            }
            let range = effectiveRange(in: textView, expandsEmptySelection: true)
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .grimoraBody
                let newSize = max(8, min(72, font.pointSize + delta))
                let converted = NSFontManager.shared.convert(font, toSize: newSize)
                storage.addAttribute(.font, value: converted, range: subrange)
            }
        }

        private func continueListOrNewline(in textView: NSTextView) -> Bool {
            guard let result = RichTextLineEditing.continueListOrNewline(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange(),
                fallbackAttributes: textView.typingAttributes
            ) else {
                return false
            }
            apply(result, to: textView)
            return true
        }

        private func insert(_ text: String, in textView: NSTextView) {
            let result = RichTextLineEditing.insert(
                text,
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange(),
                fallbackAttributes: textView.typingAttributes
            )
            apply(result, to: textView)
        }

        private func adjustZoom(by delta: CGFloat, in textView: NSTextView) {
            guard let scrollView = textView.enclosingScrollView else {
                return
            }
            setZoom(scrollView.magnification + delta, in: textView)
        }

        private func setZoom(_ scale: CGFloat, in textView: NSTextView) {
            guard let scrollView = textView.enclosingScrollView else {
                return
            }
            scrollView.magnification = min(scrollView.maxMagnification, max(scrollView.minMagnification, scale))
        }

        private func attributedSnapshot(from textView: NSTextView) -> NSAttributedString {
            textView.textStorage?.copy() as? NSAttributedString ?? NSAttributedString()
        }

        private func apply(_ result: RichTextEditResult, to textView: NSTextView) {
            textView.textStorage?.setAttributedString(result.attributedString)
            textView.setSelectedRange(result.selectedRange)
        }

        private func effectiveRange(in textView: NSTextView, expandsEmptySelection: Bool) -> NSRange {
            let selectedRange = textView.selectedRange()
            guard expandsEmptySelection, selectedRange.length == 0 else {
                return selectedRange
            }
            return paragraphRange(in: textView)
        }

        private func paragraphRange(in textView: NSTextView) -> NSRange {
            RichTextLineEditing.paragraphRange(in: textView.string, selectedRange: textView.selectedRange())
        }

        private func applyLink(_ url: URL, to textView: NSTextView) {
            let range = textView.selectedRange()
            if range.length == 0 {
                let attributed = NSAttributedString(
                    string: url.absoluteString,
                    attributes: [.link: url, .font: NSFont.grimoraBody]
                )
                textView.textStorage?.replaceCharacters(in: range, with: attributed)
                textView.setSelectedRange(NSRange(location: range.location + attributed.length, length: 0))
            } else {
                textView.textStorage?.addAttribute(.link, value: url, range: range)
            }
        }

        private func insertImage(data: Data, filename: String, into textView: NSTextView) {
            let fileWrapper = FileWrapper(regularFileWithContents: data)
            fileWrapper.preferredFilename = filename
            let attachment = NSTextAttachment(fileWrapper: fileWrapper)
            if let image = NSImage(data: data) {
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            }
            let attributed = NSAttributedString(attachment: attachment)
            let range = textView.selectedRange()
            textView.textStorage?.replaceCharacters(in: range, with: attributed)
            textView.setSelectedRange(NSRange(location: range.location + attributed.length, length: 0))
        }

        private func publish(_ textView: NSTextView) {
            let attributed = textView.textStorage?.copy() as? NSAttributedString ?? NSAttributedString()
            let data = RichTextDocumentIO.storedRTFDData(for: attributed)
            lastRTFDData = data
            parent.rtfdData = data
            parent.plainText = attributed.string
        }
    }
}
#endif
