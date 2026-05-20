import XCTest

@testable import GrimoraUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class CardListDescriptionEditorTests: XCTestCase {
    func testShortcutResolverMapsAppleNotesEditShortcuts() {
        assertShortcut("a", [.command, .shift], .requestAttachment)
        assertShortcut("k", [.command], .requestLink)

        assertShortcut("t", [.command, .shift], .action(.title))
        assertShortcut("h", [.command, .shift], .action(.heading))
        assertShortcut("j", [.command, .shift], .action(.subheading))
        assertShortcut("b", [.command, .shift], .action(.body))
        assertShortcut("m", [.command, .shift], .action(.monostyled))

        assertShortcut("b", [.command], .action(.bold))
        assertShortcut("i", [.command], .action(.italic))
        assertShortcut("u", [.command], .action(.underline))
        assertShortcut("e", [.command, .shift], .action(.highlight))

        assertShortcut("7", [.command, .shift], .action(.bulletedList))
        assertShortcut("8", [.command, .shift], .action(.dashedList))
        assertShortcut("9", [.command, .shift], .action(.numberedList))
        assertShortcut("l", [.command, .shift], .action(.checklist))
        assertShortcut("u", [.command, .shift], .action(.toggleChecklist))
        assertShortcut("'", [.command], .action(.quote))

        assertShortcut("=", [.command], .action(.increaseFontSize))
        assertShortcut("+", [.command], .action(.increaseFontSize))
        assertShortcut("-", [.command], .action(.decreaseFontSize))
        assertShortcut("]", [.command], .action(.indent))
        assertShortcut("[", [.command], .action(.outdent))
        assertShortcut(RichTextEditorShortcutResolver.tabInput, [], .action(.indent))
        assertShortcut(RichTextEditorShortcutResolver.tabInput, [.shift], .action(.outdent))
        assertShortcut(RichTextEditorShortcutResolver.tabInput, [.option], .action(.literalTab))

        assertShortcut(RichTextEditorShortcutResolver.returnInput, [], .action(.continueListOrNewline))
        assertShortcut(RichTextEditorShortcutResolver.returnInput, [.shift], .action(.softReturn))
        assertShortcut(RichTextEditorShortcutResolver.upArrowInput, [.command, .control], .action(.moveLineUp))
        assertShortcut(RichTextEditorShortcutResolver.downArrowInput, [.command, .control], .action(.moveLineDown))

        assertShortcut(".", [.command, .shift], .action(.zoomIn))
        assertShortcut(",", [.command, .shift], .action(.zoomOut))
        assertShortcut("0", [.command], .action(.resetZoom))
    }

    func testLinePrefixPreservesExistingAttributes() {
        let attributed = NSMutableAttributedString(string: "Ramp\nRemoval")
        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 4))

        let result = RichTextLineEditing.applyLinePrefix(
            to: attributed,
            selectedRange: NSRange(location: 0, length: attributed.length),
            style: .numbered
        )

        XCTAssertEqual(result.attributedString.string, "1. Ramp\n2. Removal")
        XCTAssertEqual(
            result.attributedString.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }

    func testChecklistToggleIndentOutdentAndMovePreserveAttributedText() throws {
        let attributed = NSMutableAttributedString(string: "- [ ] First\n- [x] Second")
        attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 8, length: 5))

        let toggled = RichTextLineEditing.toggleChecklist(in: attributed, selectedRange: NSRange(location: 0, length: attributed.length))
        XCTAssertEqual(toggled.attributedString.string, "- [x] First\n- [ ] Second")

        let indented = RichTextLineEditing.indentLines(in: toggled.attributedString, selectedRange: toggled.selectedRange)
        XCTAssertEqual(indented.attributedString.string, "    - [x] First\n    - [ ] Second")

        let outdented = RichTextLineEditing.outdentLines(in: indented.attributedString, selectedRange: indented.selectedRange)
        XCTAssertEqual(outdented.attributedString.string, "- [x] First\n- [ ] Second")
        XCTAssertEqual(
            outdented.attributedString.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )

        let moved = try XCTUnwrap(
            RichTextLineEditing.moveLines(
                in: outdented.attributedString,
                selectedRange: NSRange(location: 0, length: 0),
                direction: .down
            )
        )
        XCTAssertEqual(moved.attributedString.string, "- [ ] Second\n- [x] First")
        XCTAssertEqual(
            moved.attributedString.attribute(.strikethroughStyle, at: 21, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }

    func testReturnContinuationSoftReturnAndLiteralTabTransforms() throws {
        let list = NSAttributedString(string: "1. Keep")
        let continued = try XCTUnwrap(
            RichTextLineEditing.continueListOrNewline(
                in: list,
                selectedRange: NSRange(location: list.length, length: 0)
            )
        )
        XCTAssertEqual(continued.attributedString.string, "1. Keep\n2. ")

        let emptyListItem = NSAttributedString(string: "1. Keep\n2. ")
        let ended = try XCTUnwrap(
            RichTextLineEditing.continueListOrNewline(
                in: emptyListItem,
                selectedRange: NSRange(location: emptyListItem.length, length: 0)
            )
        )
        XCTAssertEqual(ended.attributedString.string, "1. Keep\n")

        let softReturn = RichTextLineEditing.insert(
            "\n",
            in: NSAttributedString(string: "- Keep"),
            selectedRange: NSRange(location: 6, length: 0)
        )
        XCTAssertEqual(softReturn.attributedString.string, "- Keep\n")

        let literalTab = RichTextLineEditing.insert(
            "\t",
            in: NSAttributedString(string: "- Keep"),
            selectedRange: NSRange(location: 2, length: 0)
        )
        XCTAssertEqual(literalTab.attributedString.string, "- \tKeep")
    }

    func testInlineStyleToggleAddsAndRemovesAttributes() throws {
        let attributed = NSAttributedString(string: "Marked")
        let highlighted = RichTextInlineStyleEditing.togglingAttribute(
            .backgroundColor,
            value: "yellow",
            in: attributed,
            selectedRange: NSRange(location: 0, length: attributed.length),
            typingAttributes: [:]
        )

        let highlightedString = try XCTUnwrap(highlighted.attributedString)
        XCTAssertEqual(highlightedString.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? String, "yellow")

        let unhighlighted = RichTextInlineStyleEditing.togglingAttribute(
            .backgroundColor,
            value: "yellow",
            in: highlightedString,
            selectedRange: NSRange(location: 0, length: highlightedString.length),
            typingAttributes: [:]
        )
        XCTAssertNil(unhighlighted.attributedString?.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let typing = RichTextInlineStyleEditing.togglingAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            in: attributed,
            selectedRange: NSRange(location: 0, length: 0),
            typingAttributes: [:]
        )
        XCTAssertEqual(typing.typingAttributes?[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }

    private func assertShortcut(
        _ input: String,
        _ modifiers: Set<RichTextEditorShortcutModifier>,
        _ expected: RichTextEditorShortcut,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            RichTextEditorShortcutResolver.shortcut(input: input, modifiers: modifiers),
            expected,
            file: file,
            line: line
        )
    }
}
