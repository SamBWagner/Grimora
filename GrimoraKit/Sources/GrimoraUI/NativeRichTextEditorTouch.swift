import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

#if os(iOS) || os(visionOS)
@MainActor
private final class NotesShortcutTextView: UITextView {
    var shortcutHandler: ((RichTextEditorShortcut) -> Bool)?

    override var keyCommands: [UIKeyCommand]? {
        [
            command("t", modifiers: [.command, .shift], title: "Title"),
            command("h", modifiers: [.command, .shift], title: "Heading"),
            command("j", modifiers: [.command, .shift], title: "Subheading"),
            command("b", modifiers: [.command, .shift], title: "Body"),
            command("m", modifiers: [.command, .shift], title: "Monostyled"),
            command("e", modifiers: [.command, .shift], title: "Highlight"),
            command("7", modifiers: [.command, .shift], title: "Bulleted List"),
            command("8", modifiers: [.command, .shift], title: "Dashed List"),
            command("9", modifiers: [.command, .shift], title: "Numbered List"),
            command("l", modifiers: [.command, .shift], title: "Checklist"),
            command("u", modifiers: [.command, .shift], title: "Toggle Checklist"),
            command("a", modifiers: [.command, .shift], title: "Attach Image"),
            command(".", modifiers: [.command, .shift], title: "Zoom In"),
            command(",", modifiers: [.command, .shift], title: "Zoom Out"),
            command("0", modifiers: [.command], title: "Reset Zoom"),
            command("b", modifiers: [.command], title: "Bold"),
            command("i", modifiers: [.command], title: "Italic"),
            command("u", modifiers: [.command], title: "Underline"),
            command("k", modifiers: [.command], title: "Link"),
            command("'", modifiers: [.command], title: "Quote"),
            command("=", modifiers: [.command], title: "Increase Font Size"),
            command("+", modifiers: [.command], title: "Increase Font Size"),
            command("-", modifiers: [.command], title: "Decrease Font Size"),
            command("]", modifiers: [.command], title: "Indent"),
            command("[", modifiers: [.command], title: "Outdent"),
            command(RichTextEditorShortcutResolver.tabInput, modifiers: [], title: "Indent"),
            command(RichTextEditorShortcutResolver.tabInput, modifiers: [.shift], title: "Outdent"),
            command(RichTextEditorShortcutResolver.tabInput, modifiers: [.alternate], title: "Insert Tab"),
            command(RichTextEditorShortcutResolver.returnInput, modifiers: [.shift], title: "Soft Return"),
            command(UIKeyCommand.inputUpArrow, modifiers: [.command, .control], title: "Move Line Up"),
            command(UIKeyCommand.inputDownArrow, modifiers: [.command, .control], title: "Move Line Down"),
        ]
    }

    private func command(
        _ input: String,
        modifiers: UIKeyModifierFlags,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: #selector(handleKeyCommand(_:)))
        command.discoverabilityTitle = title
        return command
    }

    @objc private func handleKeyCommand(_ sender: UIKeyCommand) {
        guard let shortcut = RichTextEditorShortcut(keyCommand: sender) else {
            return
        }
        _ = shortcutHandler?(shortcut)
    }

    override func insertText(_ text: String) {
        if text == "\n",
           shortcutHandler?(.action(.continueListOrNewline)) == true
        {
            return
        }
        super.insertText(text)
    }
}

private extension RichTextEditorShortcut {
    @MainActor
    init?(keyCommand: UIKeyCommand) {
        var modifiers = Set<RichTextEditorShortcutModifier>()
        if keyCommand.modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if keyCommand.modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if keyCommand.modifierFlags.contains(.alternate) {
            modifiers.insert(.option)
        }
        if keyCommand.modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }

        guard let shortcut = RichTextEditorShortcutResolver.shortcut(
            input: keyCommand.input,
            modifiers: modifiers
        ) else {
            return nil
        }
        self = shortcut
    }
}

struct NativeRichTextEditor: UIViewRepresentable {
    @Binding var rtfdData: Data?
    @Binding var plainText: String
    @Binding var command: RichTextEditorCommand?
    var onRequestLink: () -> Void
    var onRequestAttachment: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = NotesShortcutTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.font = .grimoraBody
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.attributedText = RichTextDocumentIO.attributedString(rtfdData: rtfdData, plainText: plainText)
        textView.shortcutHandler = { shortcut in
            context.coordinator.handle(shortcut, in: textView)
        }
        context.coordinator.textView = textView
        context.coordinator.lastRTFDData = rtfdData
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastRTFDData != rtfdData {
            textView.attributedText = RichTextDocumentIO.attributedString(rtfdData: rtfdData, plainText: plainText)
            context.coordinator.lastRTFDData = rtfdData
        }

        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.action, to: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeRichTextEditor
        weak var textView: UITextView?
        var lastRTFDData: Data?
        var lastCommandID: UUID?

        init(parent: NativeRichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            publish(textView)
        }

        @discardableResult
        func apply(_ action: RichTextEditorAction, to textView: UITextView) -> Bool {
            switch action {
            case .title:
                applyFont(.systemFont(ofSize: 28, weight: .bold), to: textView, expandsEmptySelection: true)
            case .heading:
                applyFont(.systemFont(ofSize: 20, weight: .semibold), to: textView, expandsEmptySelection: true)
            case .subheading:
                applyFont(.systemFont(ofSize: 17, weight: .semibold), to: textView, expandsEmptySelection: true)
            case .body:
                applyFont(.grimoraBody, to: textView, expandsEmptySelection: true)
            case .monostyled:
                applyFont(.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular), to: textView, expandsEmptySelection: true)
            case .bold:
                applySymbolicTrait(.traitBold, to: textView)
            case .italic:
                applySymbolicTrait(.traitItalic, to: textView)
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
            case .zoomIn, .zoomOut, .resetZoom:
                return true
            case .link(let url):
                applyLink(url, to: textView)
            case .image(let data, _, let typeIdentifier):
                insertImage(data: data, typeIdentifier: typeIdentifier, into: textView)
            }
            publish(textView)
            return true
        }

        func handle(_ shortcut: RichTextEditorShortcut, in textView: UITextView) -> Bool {
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
            _ font: UIFont,
            to textView: UITextView,
            expandsEmptySelection: Bool = false
        ) {
            let range = effectiveRange(in: textView, expandsEmptySelection: expandsEmptySelection)
            if range.length == 0 {
                textView.typingAttributes[.font] = font
            } else {
                textView.textStorage.addAttribute(.font, value: font, range: range)
            }
        }

        private func applySymbolicTrait(_ trait: UIFontDescriptor.SymbolicTraits, to textView: UITextView) {
            let range = textView.selectedRange
            let currentFont = (range.length == 0 ? textView.typingAttributes[.font] : textView.textStorage.attribute(.font, at: max(0, range.location - 1), effectiveRange: nil)) as? UIFont ?? .grimoraBody
            var traits = currentFont.fontDescriptor.symbolicTraits
            if traits.contains(trait) {
                traits.remove(trait)
            } else {
                traits.insert(trait)
            }
            guard let descriptor = currentFont.fontDescriptor.withSymbolicTraits(traits) else {
                return
            }
            applyFont(UIFont(descriptor: descriptor, size: currentFont.pointSize), to: textView)
        }

        private func toggleStyleAttribute(
            _ key: NSAttributedString.Key,
            value: Any,
            in textView: UITextView
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
                let selectedRange = textView.selectedRange
                textView.attributedText = attributedString
                textView.selectedRange = selectedRange
            }
        }

        private func applyLinePrefix(in textView: UITextView, style: LinePrefixStyle) {
            let result = RichTextLineEditing.applyLinePrefix(
                to: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange,
                style: style,
                fallbackAttributes: textView.typingAttributes
            )
            apply(result, to: textView)
        }

        private func toggleChecklist(in textView: UITextView) {
            let result = RichTextLineEditing.toggleChecklist(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange
            )
            apply(result, to: textView)
        }

        private func indentSelectedLines(in textView: UITextView) {
            let result = RichTextLineEditing.indentLines(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange,
                fallbackAttributes: textView.typingAttributes
            )
            apply(result, to: textView)
        }

        private func outdentSelectedLines(in textView: UITextView) {
            let result = RichTextLineEditing.outdentLines(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange
            )
            apply(result, to: textView)
        }

        private func moveSelectedLines(in textView: UITextView, direction: LineMoveDirection) {
            guard let result = RichTextLineEditing.moveLines(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange,
                direction: direction
            ) else {
                return
            }
            apply(result, to: textView)
        }

        private func adjustFontSize(by delta: CGFloat, in textView: UITextView) {
            let range = effectiveRange(in: textView, expandsEmptySelection: true)
            textView.textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? UIFont ?? .grimoraBody
                let newSize = max(8, min(72, font.pointSize + delta))
                textView.textStorage.addAttribute(
                    .font,
                    value: UIFont(descriptor: font.fontDescriptor, size: newSize),
                    range: subrange
                )
            }
        }

        private func continueListOrNewline(in textView: UITextView) -> Bool {
            guard let result = RichTextLineEditing.continueListOrNewline(
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange,
                fallbackAttributes: textView.typingAttributes
            ) else {
                return false
            }
            apply(result, to: textView)
            return true
        }

        private func insert(_ text: String, in textView: UITextView) {
            let result = RichTextLineEditing.insert(
                text,
                in: attributedSnapshot(from: textView),
                selectedRange: textView.selectedRange,
                fallbackAttributes: textView.typingAttributes
            )
            apply(result, to: textView)
        }

        private func attributedSnapshot(from textView: UITextView) -> NSAttributedString {
            textView.attributedText ?? NSAttributedString()
        }

        private func apply(_ result: RichTextEditResult, to textView: UITextView) {
            textView.attributedText = result.attributedString
            textView.selectedRange = result.selectedRange
        }

        private func effectiveRange(in textView: UITextView, expandsEmptySelection: Bool) -> NSRange {
            let selectedRange = textView.selectedRange
            guard expandsEmptySelection, selectedRange.length == 0 else {
                return selectedRange
            }
            return paragraphRange(in: textView)
        }

        private func paragraphRange(in textView: UITextView) -> NSRange {
            RichTextLineEditing.paragraphRange(in: textView.text, selectedRange: textView.selectedRange)
        }

        private func applyLink(_ url: URL, to textView: UITextView) {
            let range = textView.selectedRange
            if range.length == 0 {
                let attributed = NSAttributedString(
                    string: url.absoluteString,
                    attributes: [.link: url, .font: UIFont.grimoraBody]
                )
                textView.textStorage.replaceCharacters(in: range, with: attributed)
                textView.selectedRange = NSRange(location: range.location + attributed.length, length: 0)
            } else {
                textView.textStorage.addAttribute(.link, value: url, range: range)
            }
        }

        private func insertImage(data: Data, typeIdentifier: String, into textView: UITextView) {
            let attachment = NSTextAttachment(data: data, ofType: typeIdentifier)
            if let image = UIImage(data: data) {
                attachment.image = image
                let maxWidth = max(120, textView.bounds.width - 32)
                let scale = min(1, maxWidth / max(image.size.width, 1))
                attachment.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: image.size.width * scale,
                    height: image.size.height * scale
                )
            }
            let attributed = NSAttributedString(attachment: attachment)
            let range = textView.selectedRange
            textView.textStorage.replaceCharacters(in: range, with: attributed)
            textView.selectedRange = NSRange(location: range.location + attributed.length, length: 0)
        }

        private func publish(_ textView: UITextView) {
            let attributed = textView.attributedText ?? NSAttributedString()
            let data = RichTextDocumentIO.storedRTFDData(for: attributed)
            lastRTFDData = data
            parent.rtfdData = data
            parent.plainText = attributed.string
        }
    }
}
#endif
