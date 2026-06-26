import CoreGraphics
import GrimoraCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

@Observable
@MainActor
final class GridZoomController {
    static weak var activeForCommands: GridZoomController? {
        didSet {
            #if os(macOS)
            MacGridZoomEventMonitor.installIfNeeded()
            #endif
        }
    }

    static let defaultScale = 1.0
    static let scaleRange = 0.7...1.6
    static let buttonStepFactor = 1.12
    static let enlargedImageScaleThreshold = 1.0
    static let defaultMinimumColumnWidth: CGFloat = 240
    static let defaultMaximumColumnWidth: CGFloat = 318
    static let gridHorizontalContentPadding: CGFloat = 48

    private static let scaleEpsilon = 0.0001

    private(set) var scale: Double

    init(scale: Double = GridZoomController.defaultScale) {
        self.scale = Self.clamped(scale)
    }

    var minimumColumnWidth: CGFloat {
        Self.defaultMinimumColumnWidth * scale
    }

    var maximumColumnWidth: CGFloat {
        Self.defaultMaximumColumnWidth * scale
    }

    var minimumSingleColumnContentWidth: CGFloat {
        minimumColumnWidth + Self.gridHorizontalContentPadding
    }

    var visibleImageQuality: CardImageQuality {
        scale >= Self.enlargedImageScaleThreshold ? .normal : .small
    }

    var canZoomIn: Bool {
        scale < Self.scaleRange.upperBound - Self.scaleEpsilon
    }

    var canZoomOut: Bool {
        scale > Self.scaleRange.lowerBound + Self.scaleEpsilon
    }

    var canReset: Bool {
        abs(scale - Self.defaultScale) > Self.scaleEpsilon
    }

    func zoomIn() {
        setScale(scale * Self.buttonStepFactor)
    }

    func zoomOut() {
        setScale(scale / Self.buttonStepFactor)
    }

    func reset() {
        setScale(Self.defaultScale)
    }

    func setMagnifiedScale(startScale: Double, magnification: Double) {
        setScale(magnifiedScale(startScale: startScale, magnification: magnification))
    }

    /// The clamped scale a pinch would commit to, without mutating state.
    ///
    /// Used to drive the live on-screen pinch transform so it stops growing
    /// exactly at the supported bounds rather than overshooting.
    func magnifiedScale(startScale: Double, magnification: Double) -> Double {
        guard magnification.isFinite else {
            return scale
        }

        return Self.clamped(startScale * magnification)
    }

    private func setScale(_ newScale: Double) {
        scale = Self.clamped(newScale)
    }

    private static func clamped(_ scale: Double) -> Double {
        guard scale.isFinite else {
            return defaultScale
        }

        return min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }
}

#if os(macOS)
@MainActor
private enum MacGridZoomEventMonitor {
    private static var monitor: Any?

    static func installIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let character = event.charactersIgnoringModifiers?.lowercased()

            if flags == [.command, .shift], character == "." {
                GridZoomController.activeForCommands?.zoomIn()
                return nil
            }

            if flags == [.command, .shift], character == "," {
                GridZoomController.activeForCommands?.zoomOut()
                return nil
            }

            if flags == [.command], character == "0" {
                GridZoomController.activeForCommands?.reset()
                return nil
            }

            return event
        }
    }
}
#endif

@MainActor
enum GridZoomAvailability {
    static var isSupported: Bool {
        #if os(macOS) || os(visionOS)
        true
        #elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }
}
