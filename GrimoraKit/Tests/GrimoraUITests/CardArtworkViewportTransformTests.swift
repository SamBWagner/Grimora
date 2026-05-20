import CoreGraphics
import XCTest

@testable import GrimoraUI

final class CardArtworkViewportTransformTests: XCTestCase {
    func testNoRotationUsesIdentityTransform() {
        let transform = cardArtworkOverflowTransform(
            for: CGSize(width: 200, height: 280),
            frame: CGRect(x: 100, y: 0, width: 200, height: 280),
            rotationDegrees: 0,
            viewportFrame: CGRect(x: 80, y: 0, width: 520, height: 800)
        )

        XCTAssertEqual(transform, CardArtworkOverflowTransform(scale: 1, offsetX: 0))
    }

    func testQuarterTurnNearLeftEdgeShiftsRightInsideViewport() {
        let transform = cardArtworkOverflowTransform(
            for: CGSize(width: 200, height: 300),
            frame: CGRect(x: 100, y: 0, width: 200, height: 300),
            rotationDegrees: 90,
            viewportFrame: CGRect(x: 120, y: 0, width: 600, height: 800)
        )

        XCTAssertEqual(transform.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(transform.offsetX, 80, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(visualMinX(frameMidX: 200, sizeHeight: 300, transform: transform), 130)
    }

    func testQuarterTurnNearRightEdgeShiftsLeftInsideViewport() {
        let transform = cardArtworkOverflowTransform(
            for: CGSize(width: 200, height: 300),
            frame: CGRect(x: 620, y: 0, width: 200, height: 300),
            rotationDegrees: 90,
            viewportFrame: CGRect(x: 100, y: 0, width: 700, height: 800)
        )

        XCTAssertEqual(transform.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(transform.offsetX, -80, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(visualMaxX(frameMidX: 720, sizeHeight: 300, transform: transform), 790)
    }

    func testNarrowViewportScalesQuarterTurnToFit() {
        let transform = cardArtworkOverflowTransform(
            for: CGSize(width: 200, height: 300),
            frame: CGRect(x: 110, y: 0, width: 200, height: 300),
            rotationDegrees: 90,
            viewportFrame: CGRect(x: 100, y: 0, width: 220, height: 800)
        )

        XCTAssertEqual(transform.scale, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(transform.offsetX, 0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(visualMinX(frameMidX: 210, sizeHeight: 300, transform: transform), 110)
        XCTAssertLessThanOrEqual(visualMaxX(frameMidX: 210, sizeHeight: 300, transform: transform), 310)
    }

    func testMaximumVisualWidthScalesQuarterTurnWithinGridAllowance() {
        let transform = cardArtworkOverflowTransform(
            for: CGSize(width: 200, height: 300),
            frame: CGRect(x: 200, y: 0, width: 200, height: 300),
            rotationDegrees: 90,
            viewportFrame: CGRect(x: 100, y: 0, width: 900, height: 800),
            maximumVisualWidth: 212
        )

        XCTAssertEqual(transform.scale, 212.0 / 300.0, accuracy: 0.0001)
        XCTAssertEqual(transform.offsetX, 0, accuracy: 0.0001)
        XCTAssertEqual(
            visualMaxX(frameMidX: 300, sizeHeight: 300, transform: transform)
                - visualMinX(frameMidX: 300, sizeHeight: 300, transform: transform),
            212,
            accuracy: 0.0001
        )
    }

    func testReservedLayoutWidthExpandsForOverflowingQuarterTurnArtwork() {
        let width = cardArtworkReservedLayoutWidth(
            baseWidth: 340,
            aspectRatio: 0.716,
            hasVisualOverflow: true
        )

        XCTAssertEqual(width, 340 / 0.716, accuracy: 0.0001)
    }

    func testReservedLayoutWidthRemainsBaseWidthWithoutOverflow() {
        let width = cardArtworkReservedLayoutWidth(
            baseWidth: 340,
            aspectRatio: 0.716,
            hasVisualOverflow: false
        )

        XCTAssertEqual(width, 340, accuracy: 0.0001)
    }

    func testLandscapeArtworkLayoutUsesInverseAspectRatio() {
        let aspectRatio = cardArtworkVisualAspectRatio(
            baseAspectRatio: 0.716,
            usesLandscapeLayout: true
        )

        XCTAssertEqual(aspectRatio, 1 / 0.716, accuracy: 0.0001)
    }

    func testPortraitArtworkLayoutKeepsBaseAspectRatio() {
        let aspectRatio = cardArtworkVisualAspectRatio(
            baseAspectRatio: 0.716,
            usesLandscapeLayout: false
        )

        XCTAssertEqual(aspectRatio, 0.716, accuracy: 0.0001)
    }

    func testLandscapeArtworkLayoutSwapsSourceSizeInsideVisualFrame() {
        let sourceSize = cardArtworkSourceSize(
            forVisualSize: CGSize(width: 300, height: 214.8),
            usesLandscapeLayout: true
        )

        XCTAssertEqual(sourceSize.width, 214.8, accuracy: 0.0001)
        XCTAssertEqual(sourceSize.height, 300, accuracy: 0.0001)
    }

    func testPortraitArtworkFitsInsideReservedLandscapeFrame() {
        let sourceSize = cardArtworkSourceSize(
            forVisualSize: CGSize(width: 300, height: 214.8),
            rotationDegrees: 0,
            usesLandscapeLayout: true
        )

        XCTAssertEqual(sourceSize.width, 153.7968, accuracy: 0.0001)
        XCTAssertEqual(sourceSize.height, 214.8, accuracy: 0.0001)
    }

    func testLandscapeGridItemExpandsToArtworkHeight() {
        let width = adaptiveCardGridItemWidth(
            portraitWidth: 240,
            availableWidth: 900,
            usesLandscapeLayout: true
        )

        XCTAssertEqual(width, 240 / cardArtworkAspectRatio, accuracy: 0.0001)
    }

    func testLandscapeGridItemClampsToAvailableWidth() {
        let width = adaptiveCardGridItemWidth(
            portraitWidth: 240,
            availableWidth: 260,
            usesLandscapeLayout: true
        )

        XCTAssertEqual(width, 260, accuracy: 0.0001)
    }

    func testAdaptiveRowsReserveRealWidthForLandscapeCards() {
        let rows = adaptiveCardGridRows(
            items: ["landscape", "portrait", "portrait-2"],
            id: { $0 },
            landscapeItemIDs: ["landscape"],
            availableWidth: 920,
            minimumColumnWidth: 240,
            maximumColumnWidth: 318,
            spacing: 18
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.id), ["landscape", "portrait", "portrait-2"])
        XCTAssertGreaterThan(rows[0][0].width, rows[0][1].width)
        XCTAssertEqual(rowWidth(rows[0], spacing: 18), 920, accuracy: 0.0001)
    }

    func testAdaptiveRowsFitFourLandscapeCardsWhenViewportAllows() {
        let rows = adaptiveCardGridRows(
            items: ["battle-1", "battle-2", "battle-3", "battle-4"],
            id: { $0 },
            landscapeItemIDs: ["battle-1", "battle-2", "battle-3", "battle-4"],
            availableWidth: 1475,
            minimumColumnWidth: 240,
            maximumColumnWidth: 318,
            spacing: 18
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.id), ["battle-1", "battle-2", "battle-3", "battle-4"])
        XCTAssertEqual(rowWidth(rows[0], spacing: 18), 1475, accuracy: 0.0001)
    }

    func testAdaptiveRowsKeepShortLandscapeRowsAtPreferredScale() {
        let rows = adaptiveCardGridRows(
            items: ["battle-1", "battle-2", "battle-3"],
            id: { $0 },
            landscapeItemIDs: ["battle-1", "battle-2", "battle-3"],
            availableWidth: 1475,
            minimumColumnWidth: 240,
            maximumColumnWidth: 318,
            spacing: 18
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.id), ["battle-1", "battle-2", "battle-3"])
        XCTAssertLessThan(rowWidth(rows[0], spacing: 18), 1475)
        XCTAssertLessThanOrEqual(rows[0][0].width, 318 / cardArtworkAspectRatio)
    }

    func testAdaptiveRowsKeepSingleColumnAtPreferredScaleByDefault() {
        let rows = adaptiveCardGridRows(
            items: ["portrait"],
            id: { $0 },
            landscapeItemIDs: [],
            availableWidth: 345,
            minimumColumnWidth: 240,
            maximumColumnWidth: 318,
            spacing: 18
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.id), ["portrait"])
        XCTAssertEqual(rows[0][0].width, 318, accuracy: 0.0001)
    }

    func testAdaptiveRowsCanFillSingleColumnViewport() {
        let rows = adaptiveCardGridRows(
            items: ["portrait"],
            id: { $0 },
            landscapeItemIDs: [],
            availableWidth: 345,
            minimumColumnWidth: 240,
            maximumColumnWidth: 318,
            fillsSingleColumn: true,
            spacing: 18
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.id), ["portrait"])
        XCTAssertEqual(rows[0][0].width, 345, accuracy: 0.0001)
    }

    func testLandscapeGridFooterExtendsTileToPortraitHeight() {
        let tileWidth: CGFloat = 300
        let footerHeight = cardGridBottomBarHeight(
            tileWidth: tileWidth,
            usesLandscapeLayout: true,
            minimumHeight: 60,
            artworkAspectRatio: 0.716
        )
        let landscapeArtworkHeight = tileWidth * 0.716

        XCTAssertEqual(footerHeight, 145.2, accuracy: 0.0001)
        XCTAssertEqual(landscapeArtworkHeight + footerHeight, tileWidth + 60, accuracy: 0.0001)
    }

    func testLandscapeGridFooterAccountsForSelectionChromeInset() {
        let tileWidth: CGFloat = 347.5
        let chromeInset: CGFloat = 14
        let footerHeight = cardGridBottomBarHeight(
            tileWidth: tileWidth,
            usesLandscapeLayout: true,
            minimumHeight: 60,
            artworkAspectRatio: 0.716,
            landscapeLayoutHorizontalInset: chromeInset
        )
        let portraitArtworkWidth = (tileWidth + chromeInset) * 0.716 - chromeInset
        let portraitContentHeight = portraitArtworkWidth / 0.716 + 60
        let landscapeContentHeight = tileWidth * 0.716 + footerHeight

        XCTAssertEqual(landscapeContentHeight, portraitContentHeight, accuracy: 0.0001)
    }

    func testPortraitGridFooterKeepsMinimumHeight() {
        let footerHeight = cardGridBottomBarHeight(
            tileWidth: 300,
            usesLandscapeLayout: false,
            minimumHeight: 60
        )

        XCTAssertEqual(footerHeight, 60)
    }

    func testNilViewportUsesIdentityTransform() {
        let transform = cardArtworkOverflowTransform(
            for: CGSize(width: 200, height: 300),
            frame: CGRect(x: 100, y: 0, width: 200, height: 300),
            rotationDegrees: 90,
            viewportFrame: nil
        )

        XCTAssertEqual(transform, CardArtworkOverflowTransform(scale: 1, offsetX: 0))
    }

    private func visualMinX(
        frameMidX: CGFloat,
        sizeHeight: CGFloat,
        transform: CardArtworkOverflowTransform
    ) -> CGFloat {
        frameMidX + transform.offsetX - (sizeHeight * transform.scale / 2)
    }

    private func visualMaxX(
        frameMidX: CGFloat,
        sizeHeight: CGFloat,
        transform: CardArtworkOverflowTransform
    ) -> CGFloat {
        frameMidX + transform.offsetX + (sizeHeight * transform.scale / 2)
    }

    private func rowWidth<Item, ID: Hashable>(
        _ row: [AdaptiveCardGridEntry<Item, ID>],
        spacing: CGFloat
    ) -> CGFloat {
        row.reduce(CGFloat(0)) { result, entry in
            result + entry.width
        } + (CGFloat(max(0, row.count - 1)) * spacing)
    }
}
