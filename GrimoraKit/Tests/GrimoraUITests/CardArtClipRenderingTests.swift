#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@testable import GrimoraUI

/// Renders a synthetic Magic-card scan (a circular-cornered card on a white
/// background, mimicking how Scryfall scans leave white in the rectangular
/// corners) and confirms `CardArtClipShape` masks the white fringe where the
/// previous `.continuous` clip of the same design radius left it visible.
final class CardArtClipRenderingTests: XCTestCase {
    private let renderSize = CGSize(width: 240, height: 335) // ~card aspect
    /// The synthetic card's own (circular) corner radius, in points.
    private let scanCornerRadius: CGFloat = 9
    /// The small design radius a caller might pass for art this size.
    private let designRadius: CGFloat = 6

    @MainActor
    func testContinuousClipLeavesWhiteCornerFringe() throws {
        let bitmap = try render(syntheticScan().clipShape(
            RoundedRectangle(cornerRadius: designRadius, style: .continuous)
        ))

        XCTAssertTrue(
            hasWhiteNearAnyCorner(bitmap),
            "Baseline: a continuous clip narrower than the card corner should expose white"
        )
    }

    @MainActor
    func testCardArtClipShapeRemovesWhiteCornerFringe() throws {
        let bitmap = try render(syntheticScan().clipShape(
            CardArtClipShape(minimumRadius: designRadius)
        ))

        XCTAssertFalse(
            hasWhiteNearAnyCorner(bitmap),
            "CardArtClipShape should mask the scan's white corners across the whole frame"
        )
    }

    // MARK: - Helpers

    private func syntheticScan() -> some View {
        ZStack {
            Color.white
            RoundedRectangle(cornerRadius: scanCornerRadius, style: .circular)
                .fill(Color.black)
        }
        .frame(width: renderSize.width, height: renderSize.height)
    }

    @MainActor
    private func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: renderSize.width, height: renderSize.height))
        renderer.isOpaque = false
        renderer.scale = 1
        let nsImage = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")
        let tiff = try XCTUnwrap(nsImage.tiffRepresentation, "No TIFF representation")
        return try XCTUnwrap(NSBitmapImageRep(data: tiff), "No bitmap")
    }

    /// Samples a small inset window in each corner and reports whether any
    /// opaque, near-white pixel survives (the fringe).
    private func hasWhiteNearAnyCorner(_ bitmap: NSBitmapImageRep) -> Bool {
        let w = bitmap.pixelsWide
        let h = bitmap.pixelsHigh
        let inset = 4
        let corners = [
            (0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)
        ]

        for (cx, cy) in corners {
            for dx in 0...inset {
                for dy in 0...inset {
                    let x = min(max(cx == 0 ? cx + dx : cx - dx, 0), w - 1)
                    let y = min(max(cy == 0 ? cy + dy : cy - dy, 0), h - 1)
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    if color.alphaComponent > 0.5,
                       color.redComponent > 0.85,
                       color.greenComponent > 0.85,
                       color.blueComponent > 0.85 {
                        return true
                    }
                }
            }
        }

        return false
    }
}
#endif
