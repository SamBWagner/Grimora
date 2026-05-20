import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

enum LinePrefixStyle {
    case bulleted
    case dashed
    case numbered
    case checklist
    case quote

    func prefix(for index: Int) -> String {
        switch self {
        case .bulleted:
            return "- "
        case .dashed:
            return "-- "
        case .numbered:
            return "\(index + 1). "
        case .checklist:
            return "- [ ] "
        case .quote:
            return "> "
        }
    }
}

enum LineMoveDirection {
    case up
    case down
}

private extension String {
    func strippingKnownListPrefix() -> String {
        if hasPrefix("- [ ] ") || hasPrefix("- [x] ") {
            return String(dropFirst(6))
        }
        if hasPrefix("-- ") {
            return String(dropFirst(3))
        }
        if hasPrefix("- ") || hasPrefix("> ") {
            return String(dropFirst(2))
        }

        let pattern = #"^\d+\. "#
        if let range = range(of: pattern, options: .regularExpression) {
            return String(self[range.upperBound...])
        }
        return self
    }
}

struct RichTextEditResult {
    var attributedString: NSAttributedString
    var selectedRange: NSRange
}

struct RichTextInlineStyleResult {
    var attributedString: NSAttributedString?
    var typingAttributes: [NSAttributedString.Key: Any]?
}

enum RichTextInlineStyleEditing {
    static func togglingAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in attributedString: NSAttributedString,
        selectedRange: NSRange,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> RichTextInlineStyleResult {
        guard selectedRange.length > 0 else {
            var attributes = typingAttributes
            if attributes[key] == nil {
                attributes[key] = value
            } else {
                attributes.removeValue(forKey: key)
            }
            return RichTextInlineStyleResult(attributedString: nil, typingAttributes: attributes)
        }

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let range = NSIntersectionRange(selectedRange, NSRange(location: 0, length: mutable.length))
        guard range.length > 0 else {
            return RichTextInlineStyleResult(attributedString: mutable, typingAttributes: nil)
        }

        if mutable.attribute(key, at: range.location, effectiveRange: nil) == nil {
            mutable.addAttribute(key, value: value, range: range)
        } else {
            mutable.removeAttribute(key, range: range)
        }
        return RichTextInlineStyleResult(attributedString: mutable, typingAttributes: nil)
    }
}

struct RichTextLinePrefix {
    var style: LinePrefixStyle
    var rawPrefix: String
    var number: Int?
    var isChecklistChecked: Bool?

    var length: Int {
        (rawPrefix as NSString).length
    }

    var continuationPrefix: String {
        switch style {
        case .numbered:
            return "\((number ?? 0) + 1). "
        case .checklist:
            return "- [ ] "
        default:
            return rawPrefix
        }
    }

    static func detect(in line: String) -> RichTextLinePrefix? {
        if line.hasPrefix("- [ ] ") {
            return RichTextLinePrefix(style: .checklist, rawPrefix: "- [ ] ", isChecklistChecked: false)
        }
        if line.hasPrefix("- [x] ") {
            return RichTextLinePrefix(style: .checklist, rawPrefix: "- [x] ", isChecklistChecked: true)
        }
        if line.hasPrefix("-- ") {
            return RichTextLinePrefix(style: .dashed, rawPrefix: "-- ")
        }
        if line.hasPrefix("- ") {
            return RichTextLinePrefix(style: .bulleted, rawPrefix: "- ")
        }
        if line.hasPrefix("> ") {
            return RichTextLinePrefix(style: .quote, rawPrefix: "> ")
        }

        let pattern = #"^\d+\. "#
        guard let range = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let prefix = String(line[range])
        let numberText = prefix.dropLast(2)
        return RichTextLinePrefix(style: .numbered, rawPrefix: prefix, number: Int(numberText))
    }

    func content(in line: String) -> String {
        guard line.count >= rawPrefix.count else {
            return ""
        }
        return String(line.dropFirst(rawPrefix.count))
    }
}

enum RichTextLineEditing {
    static func paragraphRange(in text: String, selectedRange: NSRange) -> NSRange {
        let string = text as NSString
        guard string.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let location: Int
        if selectedRange.location >= string.length, string.length > 0 {
            let lastCharacter = string.substring(with: NSRange(location: string.length - 1, length: 1))
            location = lastCharacter.rangeOfCharacter(from: .newlines) == nil ? string.length - 1 : string.length
        } else {
            location = min(selectedRange.location, string.length)
        }
        let length = min(selectedRange.length, string.length - location)
        return string.paragraphRange(for: NSRange(location: location, length: length))
    }

    static func applyLinePrefix(
        to attributedString: NSAttributedString,
        selectedRange: NSRange,
        style: LinePrefixStyle,
        fallbackAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> RichTextEditResult {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let paragraphRange = paragraphRange(in: mutable.string, selectedRange: selectedRange)
        let lines = lineContentRanges(in: mutable.string as NSString, paragraphRange: paragraphRange)
        var itemIndex = 0
        var delta = 0
        var edits: [(range: NSRange, removeLength: Int, prefix: String)] = []
        let shouldPrefixSingleEmptyLine = selectedRange.length == 0 && lines.count == 1

        for range in lines {
            let text = (mutable.string as NSString).substring(with: range)
            guard !text.isEmpty || shouldPrefixSingleEmptyLine else {
                continue
            }
            let removeLength = RichTextLinePrefix.detect(in: text)?.length ?? 0
            let prefix = style.prefix(for: itemIndex)
            itemIndex += 1
            edits.append((range, removeLength, prefix))
        }

        for edit in edits.reversed() {
            let attributes = attributesForInsertion(in: mutable, at: edit.range.location, fallback: fallbackAttributes)
            if edit.removeLength > 0 {
                mutable.deleteCharacters(in: NSRange(location: edit.range.location, length: edit.removeLength))
            }
            mutable.insert(NSAttributedString(string: edit.prefix, attributes: attributes), at: edit.range.location)
            delta += (edit.prefix as NSString).length - edit.removeLength
        }

        return RichTextEditResult(
            attributedString: mutable,
            selectedRange: editedSelection(startingAt: paragraphRange.location, originalLength: paragraphRange.length, delta: delta, finalLength: mutable.length)
        )
    }

    static func toggleChecklist(
        in attributedString: NSAttributedString,
        selectedRange: NSRange
    ) -> RichTextEditResult {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let paragraphRange = paragraphRange(in: mutable.string, selectedRange: selectedRange)
        let lines = lineContentRanges(in: mutable.string as NSString, paragraphRange: paragraphRange)

        for range in lines.reversed() {
            let text = (mutable.string as NSString).substring(with: range)
            guard let prefix = RichTextLinePrefix.detect(in: text),
                  prefix.style == .checklist,
                  range.length >= prefix.length
            else {
                continue
            }
            let marker = prefix.isChecklistChecked == true ? " " : "x"
            mutable.replaceCharacters(in: NSRange(location: range.location + 3, length: 1), with: marker)
        }

        return RichTextEditResult(attributedString: mutable, selectedRange: paragraphRange)
    }

    static func indentLines(
        in attributedString: NSAttributedString,
        selectedRange: NSRange,
        fallbackAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> RichTextEditResult {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let paragraphRange = paragraphRange(in: mutable.string, selectedRange: selectedRange)
        let lines = lineContentRanges(in: mutable.string as NSString, paragraphRange: paragraphRange)
        var delta = 0

        for range in lines.reversed() {
            let text = (mutable.string as NSString).substring(with: range)
            guard !text.isEmpty else {
                continue
            }
            let attributes = attributesForInsertion(in: mutable, at: range.location, fallback: fallbackAttributes)
            mutable.insert(NSAttributedString(string: "    ", attributes: attributes), at: range.location)
            delta += 4
        }

        return RichTextEditResult(
            attributedString: mutable,
            selectedRange: editedSelection(startingAt: paragraphRange.location, originalLength: paragraphRange.length, delta: delta, finalLength: mutable.length)
        )
    }

    static func outdentLines(
        in attributedString: NSAttributedString,
        selectedRange: NSRange
    ) -> RichTextEditResult {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let paragraphRange = paragraphRange(in: mutable.string, selectedRange: selectedRange)
        let lines = lineContentRanges(in: mutable.string as NSString, paragraphRange: paragraphRange)
        var delta = 0

        for range in lines.reversed() {
            let text = (mutable.string as NSString).substring(with: range)
            let removeLength: Int
            if text.hasPrefix("    ") {
                removeLength = 4
            } else if text.hasPrefix("\t") {
                removeLength = 1
            } else {
                continue
            }
            mutable.deleteCharacters(in: NSRange(location: range.location, length: removeLength))
            delta -= removeLength
        }

        return RichTextEditResult(
            attributedString: mutable,
            selectedRange: editedSelection(startingAt: paragraphRange.location, originalLength: paragraphRange.length, delta: delta, finalLength: mutable.length)
        )
    }

    static func moveLines(
        in attributedString: NSAttributedString,
        selectedRange: NSRange,
        direction: LineMoveDirection
    ) -> RichTextEditResult? {
        let string = attributedString.string as NSString
        let range = paragraphRange(in: attributedString.string, selectedRange: selectedRange)
        guard range.length > 0 else {
            return nil
        }

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        switch direction {
        case .up:
            guard range.location > 0 else {
                return nil
            }
            let previousRange = string.paragraphRange(for: NSRange(location: max(0, range.location - 1), length: 0))
            let selected = attributedString.attributedSubstring(from: range)
            let previous = attributedString.attributedSubstring(from: previousRange)
            let selectedEndsLine = trailingLineBoundary(in: selected) != nil
            let boundary = selectedEndsLine ? NSAttributedString() : trailingLineBoundary(in: previous) ?? fallbackLineBoundary(after: selected)
            let movedPrevious = selectedEndsLine ? previous : removingTrailingLineBoundary(from: previous)
            let replacement = NSMutableAttributedString(attributedString: selected)
            replacement.append(boundary)
            replacement.append(movedPrevious)
            mutable.replaceCharacters(
                in: NSRange(location: previousRange.location, length: previousRange.length + range.length),
                with: replacement
            )
            return RichTextEditResult(
                attributedString: mutable,
                selectedRange: NSRange(location: previousRange.location, length: selected.length + boundary.length)
            )
        case .down:
            let nextLocation = range.location + range.length
            guard nextLocation < string.length else {
                return nil
            }
            let nextRange = string.paragraphRange(for: NSRange(location: nextLocation, length: 0))
            let selected = attributedString.attributedSubstring(from: range)
            let next = attributedString.attributedSubstring(from: nextRange)
            let nextEndsLine = trailingLineBoundary(in: next) != nil
            let boundary = nextEndsLine ? NSAttributedString() : trailingLineBoundary(in: selected) ?? fallbackLineBoundary(after: next)
            let movedSelected = nextEndsLine ? selected : removingTrailingLineBoundary(from: selected)
            let replacement = NSMutableAttributedString(attributedString: next)
            replacement.append(boundary)
            replacement.append(movedSelected)
            mutable.replaceCharacters(
                in: NSRange(location: range.location, length: range.length + nextRange.length),
                with: replacement
            )
            return RichTextEditResult(
                attributedString: mutable,
                selectedRange: NSRange(location: range.location + next.length + boundary.length, length: movedSelected.length)
            )
        }
    }

    static func continueListOrNewline(
        in attributedString: NSAttributedString,
        selectedRange: NSRange,
        fallbackAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> RichTextEditResult? {
        guard selectedRange.length == 0 else {
            return nil
        }
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let paragraphRange = paragraphRange(in: mutable.string, selectedRange: selectedRange)
        let contentRange = lineContentRangeWithoutTrailingNewlines(in: mutable.string as NSString, range: paragraphRange)
        let line = (mutable.string as NSString).substring(with: contentRange)
        guard let prefix = RichTextLinePrefix.detect(in: line) else {
            return nil
        }

        if prefix.content(in: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mutable.deleteCharacters(in: NSRange(location: contentRange.location, length: prefix.length))
            return RichTextEditResult(
                attributedString: mutable,
                selectedRange: NSRange(location: contentRange.location, length: 0)
            )
        }

        let attributes = attributesForInsertion(in: mutable, at: selectedRange.location, fallback: fallbackAttributes)
        let insertion = "\n" + prefix.continuationPrefix
        mutable.replaceCharacters(
            in: selectedRange,
            with: NSAttributedString(string: insertion, attributes: attributes)
        )
        return RichTextEditResult(
            attributedString: mutable,
            selectedRange: NSRange(location: selectedRange.location + (insertion as NSString).length, length: 0)
        )
    }

    static func insert(
        _ text: String,
        in attributedString: NSAttributedString,
        selectedRange: NSRange,
        fallbackAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> RichTextEditResult {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let attributes = attributesForInsertion(in: mutable, at: selectedRange.location, fallback: fallbackAttributes)
        mutable.replaceCharacters(in: selectedRange, with: NSAttributedString(string: text, attributes: attributes))
        return RichTextEditResult(
            attributedString: mutable,
            selectedRange: NSRange(location: selectedRange.location + (text as NSString).length, length: 0)
        )
    }

    private static func lineContentRanges(in string: NSString, paragraphRange: NSRange) -> [NSRange] {
        guard paragraphRange.length > 0 else {
            return [paragraphRange]
        }

        var ranges: [NSRange] = []
        var location = paragraphRange.location
        let end = paragraphRange.location + paragraphRange.length
        while location < end {
            let lineRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let bounded = NSIntersectionRange(lineRange, paragraphRange)
            ranges.append(lineContentRangeWithoutTrailingNewlines(in: string, range: bounded))

            let next = lineRange.location + lineRange.length
            if next <= location {
                break
            }
            location = next
        }
        return ranges
    }

    private static func lineContentRangeWithoutTrailingNewlines(in string: NSString, range: NSRange) -> NSRange {
        var length = range.length
        while length > 0 {
            let character = string.substring(with: NSRange(location: range.location + length - 1, length: 1))
            if character.rangeOfCharacter(from: .newlines) == nil {
                break
            }
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private static func attributesForInsertion(
        in attributedString: NSAttributedString,
        at location: Int,
        fallback: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        guard attributedString.length > 0 else {
            return fallback
        }
        let index = max(0, min(location, attributedString.length - 1))
        var attributes = attributedString.attributes(at: index, effectiveRange: nil)
        if attributes[.font] == nil, let font = fallback[.font] {
            attributes[.font] = font
        }
        return attributes
    }

    private static func trailingLineBoundary(in attributedString: NSAttributedString) -> NSAttributedString? {
        guard attributedString.length > 0 else {
            return nil
        }
        let lastRange = NSRange(location: attributedString.length - 1, length: 1)
        let lastCharacter = (attributedString.string as NSString).substring(with: lastRange)
        guard lastCharacter.rangeOfCharacter(from: .newlines) != nil else {
            return nil
        }
        return attributedString.attributedSubstring(from: lastRange)
    }

    private static func removingTrailingLineBoundary(from attributedString: NSAttributedString) -> NSAttributedString {
        guard trailingLineBoundary(in: attributedString) != nil else {
            return attributedString
        }
        return attributedString.attributedSubstring(
            from: NSRange(location: 0, length: max(0, attributedString.length - 1))
        )
    }

    private static func fallbackLineBoundary(after attributedString: NSAttributedString) -> NSAttributedString {
        guard attributedString.length > 0 else {
            return NSAttributedString(string: "\n")
        }
        let attributes = attributedString.attributes(at: attributedString.length - 1, effectiveRange: nil)
        return NSAttributedString(string: "\n", attributes: attributes)
    }

    private static func editedSelection(
        startingAt location: Int,
        originalLength: Int,
        delta: Int,
        finalLength: Int
    ) -> NSRange {
        let safeLocation = min(location, finalLength)
        let length = max(0, min(finalLength - safeLocation, originalLength + delta))
        return NSRange(location: safeLocation, length: length)
    }
}
