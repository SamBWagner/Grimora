import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#elseif os(iOS) || os(visionOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

extension PlatformFont {
    static var grimoraBody: PlatformFont {
        #if os(macOS)
        PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
        #elseif os(iOS) || os(visionOS)
        PlatformFont.preferredFont(forTextStyle: .body)
        #endif
    }
}
