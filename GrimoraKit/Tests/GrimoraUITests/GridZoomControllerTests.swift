import CoreGraphics
import GrimoraCore
import XCTest

@testable import GrimoraUI

@MainActor
final class GridZoomControllerTests: XCTestCase {
    func testCardDisplayImageAccessibilityValueDistinguishesLoadingPreviews() {
        let remotePreview = CardRecord(
            id: "remote",
            name: "Remote Preview",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Instant",
            oracleText: "",
            smallImageURL: "https://example.test/remote-small.jpg"
        )
        XCTAssertTrue(remotePreview.isAwaitingDisplayImage)
        XCTAssertEqual(remotePreview.displayImageAccessibilityValue, "Loading Image")

        var cachedPreview = remotePreview
        cachedPreview.smallImagePath = "/tmp/remote-small.jpg"
        XCTAssertFalse(cachedPreview.isAwaitingDisplayImage)
        XCTAssertEqual(cachedPreview.displayImageAccessibilityValue, "Image")

        var detailOnlyPreview = remotePreview
        detailOnlyPreview.largeImagePath = "/tmp/remote-large.jpg"
        XCTAssertFalse(detailOnlyPreview.isAwaitingDisplayImage)
        XCTAssertEqual(detailOnlyPreview.displayImageAccessibilityValue, "Image")

        var textOnly = remotePreview
        textOnly.smallImageURL = nil
        XCTAssertFalse(textOnly.isAwaitingDisplayImage)
        XCTAssertEqual(textOnly.displayImageAccessibilityValue, "Text Only")
    }

    func testDefaultScaleAndColumnSizingUseBaselineValues() {
        let controller = GridZoomController()

        XCTAssertEqual(controller.scale, 1)
        XCTAssertEqual(controller.minimumColumnWidth, 240)
        XCTAssertEqual(controller.maximumColumnWidth, 318)
        XCTAssertEqual(controller.minimumSingleColumnContentWidth, 288)
        XCTAssertTrue(controller.canZoomIn)
        XCTAssertTrue(controller.canZoomOut)
        XCTAssertFalse(controller.canReset)
        XCTAssertEqual(controller.visibleImageQuality, .normal)
    }

    func testDefaultSizingTargetsFiveColumnsInWideMacGrid() {
        let controller = GridZoomController()
        let maxGridWidth: CGFloat = 1_500 - 48

        XCTAssertEqual(
            estimatedAdaptiveColumnCount(
                availableWidth: maxGridWidth,
                spacing: 18,
                minimumColumnWidth: controller.minimumColumnWidth
            ),
            5
        )
    }

    func testInitialScaleIsClampedToSupportedBounds() {
        XCTAssertEqual(GridZoomController(scale: 0.1).scale, 0.7)
        XCTAssertEqual(GridZoomController(scale: 5).scale, 1.6)
        XCTAssertEqual(GridZoomController(scale: .infinity).scale, 1)
    }

    func testZoomButtonsStepAndClampScale() {
        let controller = GridZoomController()

        controller.zoomIn()
        XCTAssertEqual(controller.scale, 1.12, accuracy: 0.0001)
        XCTAssertEqual(controller.minimumColumnWidth, 268.8, accuracy: 0.0001)

        controller.zoomOut()
        XCTAssertEqual(controller.scale, 1, accuracy: 0.0001)

        for _ in 0..<20 {
            controller.zoomOut()
        }
        XCTAssertEqual(controller.scale, 0.7, accuracy: 0.0001)
        XCTAssertFalse(controller.canZoomOut)

        for _ in 0..<40 {
            controller.zoomIn()
        }
        XCTAssertEqual(controller.scale, 1.6, accuracy: 0.0001)
        XCTAssertFalse(controller.canZoomIn)
    }

    func testResetReturnsToDefaultScale() {
        let controller = GridZoomController(scale: 1.35)

        XCTAssertTrue(controller.canReset)
        controller.reset()

        XCTAssertEqual(controller.scale, 1)
        XCTAssertFalse(controller.canReset)
        XCTAssertEqual(controller.visibleImageQuality, .normal)
    }

    func testMagnificationUsesGestureStartScaleAndClamps() {
        let controller = GridZoomController(scale: 1.2)

        controller.setMagnifiedScale(startScale: 1.2, magnification: 1.25)
        XCTAssertEqual(controller.scale, 1.5, accuracy: 0.0001)

        controller.setMagnifiedScale(startScale: 1.2, magnification: 10)
        XCTAssertEqual(controller.scale, 1.6, accuracy: 0.0001)

        controller.setMagnifiedScale(startScale: 1.2, magnification: 0.1)
        XCTAssertEqual(controller.scale, 0.7, accuracy: 0.0001)

        controller.setMagnifiedScale(startScale: 1.2, magnification: .nan)
        XCTAssertEqual(controller.scale, 0.7, accuracy: 0.0001)
    }

    func testVisibleImageQualitySwitchesAtEnlargedThreshold() {
        let belowThreshold = GridZoomController(scale: 0.99)
        XCTAssertEqual(belowThreshold.visibleImageQuality, .small)

        let atThreshold = GridZoomController(scale: GridZoomController.enlargedImageScaleThreshold)
        XCTAssertEqual(atThreshold.visibleImageQuality, .normal)

        let aboveThreshold = GridZoomController(scale: 1.4)
        XCTAssertEqual(aboveThreshold.visibleImageQuality, .normal)
    }

    private func estimatedAdaptiveColumnCount(
        availableWidth: CGFloat,
        spacing: CGFloat,
        minimumColumnWidth: CGFloat
    ) -> Int {
        max(Int((availableWidth + spacing) / (minimumColumnWidth + spacing)), 1)
    }
}
