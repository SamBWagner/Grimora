import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

enum RichTextDocumentIO {
    static func attributedString(rtfdData: Data?, plainText: String) -> NSAttributedString {
        if let rtfdData,
           let attributed = try? NSAttributedString(
            data: rtfdData,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
           )
        {
            return attributed
        }

        return NSAttributedString(
            string: plainText,
            attributes: [.font: PlatformFont.grimoraBody]
        )
    }

    static func storedRTFDData(for attributedString: NSAttributedString) -> Data? {
        guard attributedString.length > 0 else {
            return nil
        }
        let hasMeaningfulText =
            attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasMeaningfulText || containsAttachment(attributedString) else {
            return nil
        }

        return try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
    }

    private static func containsAttachment(_ attributedString: NSAttributedString) -> Bool {
        var foundAttachment = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value != nil {
                foundAttachment = true
                stop.pointee = true
            }
        }
        return foundAttachment
    }
}
