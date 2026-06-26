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

/// Photos-style live pinch-to-zoom for a card/tile grid.
///
/// Attach to the grid's `ScrollView` so the gesture's `startAnchor` is reported
/// in viewport coordinates. While the pinch is active the whole pane is scaled
/// as a single layer (capped to the committable range so it never overshoots the
/// limits); on release the discrete layout is committed with a spring and the
/// transform unwinds together, cross-fading into the reflowed grid. Because
/// `gridZoom.scale` is untouched mid-gesture, image quality never reloads while
/// pinching. No clipping is applied — scaled content tucks under the surrounding
/// opaque chrome just like normal scrolling.
private struct GridZoomPinchModifier: ViewModifier {
    var gridZoom: GridZoomController

    @State private var startScale: Double?
    @State private var liveMagnification: CGFloat = 1
    @State private var anchor: UnitPoint = .center

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(GridZoomAvailability.isSupported ? pinch : nil)
            .scaleEffect(liveMagnification, anchor: anchor)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = startScale ?? gridZoom.scale
                startScale = start
                anchor = value.startAnchor
                let target = gridZoom.magnifiedScale(
                    startScale: start,
                    magnification: value.magnification
                )
                liveMagnification = CGFloat(target / start)
            }
            .onEnded { value in
                let start = startScale ?? gridZoom.scale
                startScale = nil
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    gridZoom.setMagnifiedScale(
                        startScale: start,
                        magnification: value.magnification
                    )
                    liveMagnification = 1
                }
            }
    }
}

extension View {
    /// Adds live pinch-to-zoom that drives `gridZoom`. See `GridZoomPinchModifier`.
    func gridZoomPinch(_ gridZoom: GridZoomController) -> some View {
        modifier(GridZoomPinchModifier(gridZoom: gridZoom))
    }
}
