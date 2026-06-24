import CoreGraphics
import Foundation
import GrimoraCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

#if os(iOS)
import UIKit
#endif

final class AppStoreScreenshotUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraAppStoreScreenshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testGenerateAppStoreScreenshots() throws {
        let outputDirectory = try screenshotOutputDirectory()

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCUIDevice.shared.orientation = .portrait
            try capturePhoneScreenshots(outputDirectory: outputDirectory)
        } else {
            XCUIDevice.shared.orientation = .landscapeLeft
            settle(1.0)
            try capturePadScreenshots(outputDirectory: outputDirectory)
        }
        #elseif os(visionOS)
        try captureVisionScreenshots(outputDirectory: outputDirectory)
        #endif
    }

    @MainActor
    private func capturePhoneScreenshots(outputDirectory: URL) throws {
        var app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        settle()
        try save(app, named: "07-search-home.png", to: outputDirectory)

        let firstCard = firstElement(app, identifier: "open-card-astral-archivist")
        revealContextMenu(on: firstCard)
        settle()
        try save(app, named: "01-card-actions.png", to: outputDirectory)
        app.terminate()

        app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        activate(firstElement(app, identifier: "open-card-astral-archivist"))
        XCTAssertTrue(firstElement(app, identifier: "card-detail").waitForExistence(timeout: 5))
        settle()
        try save(app, named: "03-card-detail.png", to: outputDirectory)
        app.swipeUp()
        app.swipeUp()
        settle()
        try save(app, named: "02-card-value-details.png", to: outputDirectory)
        app.terminate()

        app = try launchSeededApp(defaultSearchText: "Verdant")
        XCTAssertTrue(firstElement(app, identifier: "open-card-verdant-compass").waitForExistence(timeout: 8))
        settle()
        try save(app, named: "06-search-filtered.png", to: outputDirectory)
        try save(app, named: "05-search-menu.png", to: outputDirectory)
        app.terminate()

        app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Weekend Build").waitForExistence(timeout: 5)
            || firstElement(app, identifier: "card-list-overview-tile-Weekend Build").waitForExistence(timeout: 5))
        settle()
        try save(app, named: "04-list-stats.png", to: outputDirectory)
        try save(app, named: "08-setup-library.png", to: outputDirectory)
    }

    @MainActor
    private func capturePadScreenshots(outputDirectory: URL) throws {
        var app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        settle()
        try save(app, named: "06-search-grid.png", to: outputDirectory)
        try save(app, named: "08-search-filtered.png", to: outputDirectory)

        activate(firstElement(app, identifier: "open-card-astral-archivist"))
        XCTAssertTrue(firstElement(app, identifier: "card-detail").waitForExistence(timeout: 5))
        settle()
        try save(app, named: "05-card-detail-expanded.png", to: outputDirectory)
        app.terminate()

        app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Weekend Build").waitForExistence(timeout: 5)
            || firstElement(app, identifier: "card-list-overview-tile-Weekend Build").waitForExistence(timeout: 5))
        settle()
        try save(app, named: "01-lists.png", to: outputDirectory)
        try save(app, named: "03-new-list.png", to: outputDirectory)

        let row = firstElement(app, identifier: "card-list-row-Weekend Build")
        if row.exists {
            activate(row)
        } else {
            activate(firstElement(app, identifier: "card-list-overview-tile-Weekend Build"))
        }
        XCTAssertTrue(firstElement(app, identifier: "card-list-detail").waitForExistence(timeout: 5)
            || firstElement(app, identifier: "card-list-view-mode-picker").waitForExistence(timeout: 5))
        settle()
        try save(app, named: "07-list-grid.png", to: outputDirectory)
        try save(app, named: "04-list-detail-printings.png", to: outputDirectory)
        try save(app, named: "02-setup-library.png", to: outputDirectory)
    }

    @MainActor
    private func captureVisionScreenshots(outputDirectory: URL) throws {
        var app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        settle()
        try save(app, named: "05-search-results.png", to: outputDirectory)
        try save(app, named: "01-setup-library.png", to: outputDirectory)
        app.terminate()

        app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Weekend Build").waitForExistence(timeout: 5)
            || firstElement(app, identifier: "card-list-overview-tile-Weekend Build").waitForExistence(timeout: 5))
        settle()
        try save(app, named: "03-lists-overview.png", to: outputDirectory)
        try save(app, named: "04-lists-overview-alt.png", to: outputDirectory)

        let row = firstElement(app, identifier: "card-list-row-Weekend Build")
        if row.exists {
            activate(row)
        } else {
            activate(firstElement(app, identifier: "card-list-overview-tile-Weekend Build"))
        }
        settle()
        try save(app, named: "02-list-detail-grid.png", to: outputDirectory)
    }

    @MainActor
    private func launchSeededApp(defaultSearchText: String = "") throws -> XCUIApplication {
        let databaseURL = try seedDatabase()
        let app = XCUIApplication()
        app.launchArguments += [
            "-\(DefaultSearchPreferenceKeys.text)",
            defaultSearchText,
            "-\(DefaultSearchPreferenceKeys.alwaysIncludedText)",
            "",
            "-\(DefaultSearchPreferenceKeys.sortMode)",
            SortMode.name.rawValue,
            "-\(DefaultSearchPreferenceKeys.sortDirection)",
            SearchSortDirection.ascending.rawValue,
            "-\(DefaultSearchPreferenceKeys.cloudSyncMode)",
            "disabled"
        ]
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = databaseURL.path
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = imageDirectory.path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraAppStoreScreenshots-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private func seedDatabase() throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let cards = try Self.fixtureCards(imageDirectory: imageDirectory)
        try database.replaceAllCards(cards)
        try database.saveMetadataValue("2026-05-23T00:00:00.000+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)

        let list = try database.createCardList(named: "Weekend Build")
        try database.setCardListViewMode(id: list.id, viewMode: .grid)
        let core = try database.createCardListCategory(inList: list.id, named: "Core")
        let tools = try database.createCardListCategory(inList: list.id, named: "Tools")
        for (index, card) in cards.enumerated() {
            let category = index.isMultiple(of: 2) ? core.id : tools.id
            try database.appendCard(card.id, toList: list.id, categoryID: category, quantity: index % 3 + 1)
        }
        return databaseURL
    }

    private var imageDirectory: URL {
        temporaryDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    private func screenshotOutputDirectory() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["GRIMORA_APP_STORE_SCREENSHOT_OUTPUT_DIR"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let url = temporaryDirectory.appendingPathComponent("CapturedScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func save(_ app: XCUIApplication, named filename: String, to directory: URL) throws {
        settle()
        #if os(visionOS)
        try requestHostSimulatorScreenshot(named: filename, to: directory)
        #else
        let screenshot = captureScreenshot(for: app)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(filename), options: .atomic)
        } catch {
            XCTContext.runActivity(named: "Direct screenshot export failed for \(filename)") { activity in
                activity.add(XCTAttachment(string: String(describing: error)))
            }
        }
        #endif
    }

    private func requestHostSimulatorScreenshot(named filename: String, to directory: URL) throws {
        let hostDirectory = URL(
            fileURLWithPath: "/private/tmp/grimora-app-store-screenshots/VisionOS-3840x2160",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let requestURL = hostDirectory.appendingPathComponent("\(filename).request")
        let capturedURL = hostDirectory.appendingPathComponent("\(filename).captured")
        try? FileManager.default.removeItem(at: requestURL)
        try? FileManager.default.removeItem(at: capturedURL)
        try filename.write(to: requestURL, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: capturedURL.path) {
                let attachment = XCTAttachment(string: "Captured by host simulator screenshot: \(filename)")
                attachment.name = filename
                attachment.lifetime = .keepAlways
                add(attachment)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        throw ScreenshotFixtureError.hostCaptureTimedOut
    }

    @MainActor
    private func captureScreenshot(for app: XCUIApplication) -> XCUIScreenshot {
        #if os(visionOS)
        return XCUIScreen.main.screenshot()
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            let window = app.windows.firstMatch
            if window.waitForExistence(timeout: 1) {
                return window.screenshot()
            }
        }
        return app.screenshot()
        #else
        return app.screenshot()
        #endif
    }

    @MainActor
    private func firstElement(_ root: XCUIElement, identifier: String) -> XCUIElement {
        root.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func button(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    @MainActor
    private func revealContextMenu(on element: XCUIElement) {
        #if os(macOS)
        element.rightClick()
        #else
        element.press(forDuration: 1.0)
        #endif
    }

    @MainActor
    private func settle(_ interval: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    private static func fixtureCards(imageDirectory: URL) throws -> [CardRecord] {
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        return try fixtureDefinitions.enumerated().map { index, definition in
            let imageURL = imageDirectory.appendingPathComponent("\(definition.id).png")
            try writeArtwork(to: imageURL, palette: definition.palette, seed: index + 11)
            return CardRecord(
                id: definition.id,
                oracleID: "\(definition.id)-oracle",
                name: definition.name,
                releasedAt: definition.releaseDate,
                setCode: definition.code,
                setName: definition.setName,
                setType: "expansion",
                collectorNumber: "\(index + 1)",
                collectorNumberNumber: index + 1,
                rarity: definition.rarity,
                rarityRank: index % 4,
                artist: "Grimora Studio",
                manaCost: definition.cost,
                manaValue: Double(index % 6 + 1),
                priceUSD: definition.price,
                colorSortKey: index,
                layout: "normal",
                typeLine: definition.kind,
                oracleText: definition.text,
                keywords: definition.keywords,
                isRealCard: true,
                printCount: 3,
                setCount: 2,
                paperPrintCount: 3,
                paperSetCount: 2,
                artistCount: 1,
                illustrationCount: 1,
                normalImagePath: imageURL.path,
                largeImagePath: imageURL.path
            )
        }
    }

    private static func writeArtwork(
        to url: URL,
        palette: ArtworkPalette,
        seed: Int
    ) throws {
        let width = 720
        let height = 1005
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotFixtureError.imageContextFailed
        }

        context.setFillColor(palette.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var random = SeededRandom(seed: UInt64(seed))

        for index in 0..<20 {
            let size = CGFloat(72 + random.nextInt(220))
            let x = CGFloat(random.nextInt(width - Int(size)))
            let y = CGFloat(random.nextInt(height - Int(size)))
            let alpha = CGFloat(0.24 + Double(random.nextInt(36)) / 100.0)
            context.setFillColor([palette.primary, palette.secondary, palette.highlight][index % 3].cgColor(alpha: alpha))
            switch index % 3 {
            case 0:
                context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            case 1:
                context.fill(CGRect(x: x, y: y, width: min(size * 1.8, CGFloat(width) - x), height: size * 0.72))
            default:
                context.beginPath()
                context.move(to: CGPoint(x: x + size * 0.5, y: y))
                context.addLine(to: CGPoint(x: x + size, y: y + size))
                context.addLine(to: CGPoint(x: x, y: y + size))
                context.closePath()
                context.fillPath()
            }
        }

        context.setStrokeColor(palette.line.cgColor(alpha: 0.5))
        context.setLineWidth(6)
        for index in 0..<9 {
            let y = CGFloat(145 + index * 84)
            context.move(to: CGPoint(x: 74, y: y))
            context.addLine(to: CGPoint(x: CGFloat(width - 74), y: y + CGFloat(random.nextInt(24) - 12)))
            context.strokePath()
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              )
        else {
            throw ScreenshotFixtureError.imageContextFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotFixtureError.imageWriteFailed
        }
    }

    private static let fixtureDefinitions: [CardFixtureDefinition] = [
        CardFixtureDefinition(
            id: "astral-archivist",
            name: "Astral Archivist",
            kind: "Scholar",
            setName: "Aurora Catalog",
            code: "ARC",
            releaseDate: "2026-01-03",
            rarity: "rare",
            cost: "3",
            text: "Catalog two discoveries. Preserve one note in your collection.",
            price: 2.40,
            keywords: ["Catalog"],
            palette: ArtworkPalette("#0c214a", "#7aa8ff", "#6a52ff", "#d7e6ff", "#7ca7d8")
        ),
        CardFixtureDefinition(
            id: "harbor-lantern",
            name: "Harbor Lantern",
            kind: "Relic",
            setName: "Tidefoundry",
            code: "TDF",
            releaseDate: "2026-01-10",
            rarity: "uncommon",
            cost: "2",
            text: "Charge once. Add a color from your saved palette.",
            price: 0.85,
            keywords: ["Charge"],
            palette: ArtworkPalette("#0d3a3a", "#5bd0ce", "#f0d35c", "#e9fffb", "#7cc8c8")
        ),
        CardFixtureDefinition(
            id: "copperbound-surveyor",
            name: "Copperbound Surveyor",
            kind: "Construct",
            setName: "Brass Garden",
            code: "BRG",
            releaseDate: "2026-02-01",
            rarity: "rare",
            cost: "4",
            text: "When this enters, inspect the top entry of any list.",
            price: 4.10,
            keywords: ["Inspect"],
            palette: ArtworkPalette("#4d211b", "#f08a5d", "#f6dc62", "#ffe5d4", "#b36a50")
        ),
        CardFixtureDefinition(
            id: "mistvale-gate",
            name: "Mistvale Gate",
            kind: "Landmark",
            setName: "Cloudline",
            code: "CLD",
            releaseDate: "2026-02-12",
            rarity: "common",
            cost: "",
            text: "Open a path. Mark one item as ready.",
            price: 1.20,
            keywords: ["Open"],
            palette: ArtworkPalette("#10334a", "#a8dadc", "#457b9d", "#f0fbff", "#7eaac6")
        ),
        CardFixtureDefinition(
            id: "quartz-drake",
            name: "Quartz Drake",
            kind: "Creature",
            setName: "Glass Peaks",
            code: "GLS",
            releaseDate: "2026-03-05",
            rarity: "mythic",
            cost: "5",
            text: "Glide. Whenever you sort a list, this gains clarity.",
            price: 7.30,
            keywords: ["Glide"],
            palette: ArtworkPalette("#27283d", "#f8f7ff", "#b8c0ff", "#ffffff", "#bfc5e8")
        ),
        CardFixtureDefinition(
            id: "verdant-compass",
            name: "Verdant Compass",
            kind: "Tool",
            setName: "Mosswork",
            code: "MSW",
            releaseDate: "2026-03-20",
            rarity: "uncommon",
            cost: "1",
            text: "Tap to find a category. If it is empty, create a new one.",
            price: 0.55,
            keywords: ["Tap"],
            palette: ArtworkPalette("#14351f", "#8ac926", "#198754", "#ecffd9", "#70a85b")
        ),
        CardFixtureDefinition(
            id: "lantern-scribe",
            name: "Lantern Scribe",
            kind: "Advisor",
            setName: "Ink Harbor",
            code: "INK",
            releaseDate: "2026-04-02",
            rarity: "common",
            cost: "2",
            text: "When you add this to a list, draw a reminder.",
            price: 0.35,
            keywords: ["Reminder"],
            palette: ArtworkPalette("#20243a", "#a0b4ff", "#d8dffb", "#ffffff", "#8a93bb")
        ),
        CardFixtureDefinition(
            id: "ember-indexer",
            name: "Ember Indexer",
            kind: "Archivist",
            setName: "Ash Ledger",
            code: "ASH",
            releaseDate: "2026-04-08",
            rarity: "rare",
            cost: "3",
            text: "Sort a saved list, then highlight one changed entry.",
            price: 3.15,
            keywords: ["Sort"],
            palette: ArtworkPalette("#462020", "#ff8a65", "#ffcc70", "#fff1df", "#bd725f")
        )
    ]
}

private struct CardFixtureDefinition {
    var id: String
    var name: String
    var kind: String
    var setName: String
    var code: String
    var releaseDate: String
    var rarity: String
    var cost: String
    var text: String
    var price: Double
    var keywords: [String]
    var palette: ArtworkPalette
}

private struct ArtworkPalette {
    var background: RGBColor
    var primary: RGBColor
    var secondary: RGBColor
    var highlight: RGBColor
    var line: RGBColor

    init(_ background: String, _ primary: String, _ secondary: String, _ highlight: String, _ line: String) {
        self.background = RGBColor(hex: background)
        self.primary = RGBColor(hex: primary)
        self.secondary = RGBColor(hex: secondary)
        self.highlight = RGBColor(hex: highlight)
        self.line = RGBColor(hex: line)
    }
}

private struct RGBColor {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(trimmed, radix: 16) ?? 0
        red = CGFloat((value >> 16) & 0xFF) / 255.0
        green = CGFloat((value >> 8) & 0xFF) / 255.0
        blue = CGFloat(value & 0xFF) / 255.0
    }

    var cgColor: CGColor {
        cgColor(alpha: 1)
    }

    func cgColor(alpha: CGFloat) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state % UInt64(max(1, upperBound)))
    }
}

private enum ScreenshotFixtureError: Error {
    case imageContextFailed
    case imageWriteFailed
    case hostCaptureTimedOut
}

private enum DefaultSearchPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let sortMode = "Grimora.defaultSearch.sortMode"
    static let sortDirection = "Grimora.defaultSearch.sortDirection"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
