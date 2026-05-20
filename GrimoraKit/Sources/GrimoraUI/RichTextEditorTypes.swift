import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct RichTextEditorCommand {
    var id = UUID()
    var action: RichTextEditorAction
}

enum RichTextEditorAction: Equatable {
    case title
    case heading
    case subheading
    case body
    case monostyled
    case bold
    case italic
    case underline
    case strikethrough
    case highlight
    case bulletedList
    case dashedList
    case numberedList
    case checklist
    case toggleChecklist
    case quote
    case increaseFontSize
    case decreaseFontSize
    case indent
    case outdent
    case moveLineUp
    case moveLineDown
    case continueListOrNewline
    case softReturn
    case literalTab
    case zoomIn
    case zoomOut
    case resetZoom
    case link(URL)
    case image(data: Data, filename: String, typeIdentifier: String)
}

enum RichTextEditorShortcut: Equatable {
    case action(RichTextEditorAction)
    case requestLink
    case requestAttachment
}

enum RichTextEditorShortcutModifier: Hashable {
    case command
    case shift
    case option
    case control
}

enum RichTextEditorShortcutResolver {
    static let upArrowInput = "\u{F700}"
    static let downArrowInput = "\u{F701}"
    static let returnInput = "\r"
    static let tabInput = "\t"

    static func shortcut(
        input rawInput: String?,
        keyCode: UInt16? = nil,
        modifiers: Set<RichTextEditorShortcutModifier>
    ) -> RichTextEditorShortcut? {
        let input = rawInput?.lowercased()
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        let control = modifiers.contains(.control)

        if command && shift && !option && !control {
            switch input {
            case "t":
                return .action(.title)
            case "h":
                return .action(.heading)
            case "j":
                return .action(.subheading)
            case "b":
                return .action(.body)
            case "m":
                return .action(.monostyled)
            case "e":
                return .action(.highlight)
            case "7":
                return .action(.bulletedList)
            case "8":
                return .action(.dashedList)
            case "9":
                return .action(.numberedList)
            case "l":
                return .action(.checklist)
            case "u":
                return .action(.toggleChecklist)
            case "a":
                return .requestAttachment
            case ".":
                return .action(.zoomIn)
            case ",":
                return .action(.zoomOut)
            default:
                return nil
            }
        }

        if command && !shift && !option && !control {
            switch input {
            case "b":
                return .action(.bold)
            case "i":
                return .action(.italic)
            case "u":
                return .action(.underline)
            case "k":
                return .requestLink
            case "'":
                return .action(.quote)
            case "0":
                return .action(.resetZoom)
            case "=", "+":
                return .action(.increaseFontSize)
            case "-":
                return .action(.decreaseFontSize)
            case "]":
                return .action(.indent)
            case "[":
                return .action(.outdent)
            default:
                return nil
            }
        }

        if command && control && !option && !shift {
            if keyCode == 126 || input == Self.upArrowInput {
                return .action(.moveLineUp)
            }
            if keyCode == 125 || input == Self.downArrowInput {
                return .action(.moveLineDown)
            }
            return nil
        }

        if !command && !control {
            if !option && input == Self.tabInput {
                return shift ? .action(.outdent) : .action(.indent)
            }
            if option && !shift && input == Self.tabInput {
                return .action(.literalTab)
            }
            if !option && input == Self.returnInput {
                return shift ? .action(.softReturn) : .action(.continueListOrNewline)
            }
        }

        return nil
    }
}
