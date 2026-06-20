import CoreGraphics
import Darwin
import Foundation
import GrimoraCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class AppStoreScreenshotUITests: XCTestCase {
    private var temporaryDirectory: URL!
    private var appDatabaseURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraMacAppStoreScreenshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        appDatabaseURL = try Self.hostHomeDirectory()
            .appendingPathComponent("Library/Containers/com.samwagner.Grimora/Data/Library/Application Support/Grimora", isDirectory: true)
            .appendingPathComponent("app-store-screenshots-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testGenerateAppStoreScreenshots() throws {
        let outputDirectory = try screenshotOutputDirectory()

        var app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        settle()
        try save(app, named: "01-search-library.png", to: outputDirectory)

        app.terminate()
        app = try launchSeededApp(defaultSearchText: "Verdant")
        XCTAssertTrue(firstElement(app, identifier: "open-card-verdant-compass").waitForExistence(timeout: 8))
        settle()
        try save(app, named: "02-filtered-search.png", to: outputDirectory)

        let createButton = firstElement(app, identifier: "create-list-button")
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        createButton.click()
        XCTAssertTrue(firstElement(app, identifier: "create-list-destination").waitForExistence(timeout: 3))
        settle()
        try save(app, named: "03-create-list.png", to: outputDirectory)
        try submitWeekendBuildList(app)
        try addCard(app, cardID: "verdant-compass", toList: "Weekend Build")
        app.terminate()

        app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-astral-archivist").waitForExistence(timeout: 8))
        let listsButton = firstElement(app, identifier: "lists-overview-sidebar-button")
        if listsButton.waitForExistence(timeout: 2) {
            listsButton.click()
            settle()
        }
        let listRow = firstElement(app, identifier: "card-list-row-Weekend Build")
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        settle()
        try save(app, named: "04-lists-overview.png", to: outputDirectory)
        listRow.click()
        settle()
        try save(app, named: "05-list-detail.png", to: outputDirectory)
    }

    @MainActor
    private func launchSeededApp(defaultSearchText: String = "") throws -> XCUIApplication {
        let fixtureJSON = try MacScreenshotFixture.fixtureCardsJSON()
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleInterfaceStyle",
            "Dark",
            "-\(MacScreenshotPreferenceKeys.text)",
            defaultSearchText,
            "-\(MacScreenshotPreferenceKeys.alwaysIncludedText)",
            "",
            "-\(MacScreenshotPreferenceKeys.sortMode)",
            SortMode.name.rawValue,
            "-\(MacScreenshotPreferenceKeys.sortDirection)",
            SearchSortDirection.ascending.rawValue,
            "-\(MacScreenshotPreferenceKeys.searchInputMode)",
            "scryfall",
            "-\(MacScreenshotPreferenceKeys.cloudSyncMode)",
            "disabled"
        ]
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = appDatabaseURL.path
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] = fixtureJSON
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraMacAppStoreScreenshots-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private static func hostHomeDirectory() throws -> URL {
        guard let passwd = Darwin.getpwuid(Darwin.getuid()),
              let directory = passwd.pointee.pw_dir
        else {
            throw NSError(
                domain: "AppStoreScreenshotUITests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to resolve host home directory."]
            )
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
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
    }

    @MainActor
    private func captureScreenshot(for app: XCUIApplication) -> XCUIScreenshot {
        let window = app.windows.firstMatch
        if window.waitForExistence(timeout: 1) {
            return window.screenshot()
        }
        return app.screenshot()
    }

    @MainActor
    private func firstElement(_ root: XCUIElement, identifier: String) -> XCUIElement {
        root.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func submitWeekendBuildList(_ app: XCUIApplication) throws {
        let nameField = app.textFields["list-import-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("Weekend Build")

        let createButton = firstElement(app, identifier: "list-import-submit-button")
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        XCTAssertTrue(createButton.isEnabled)
        createButton.click()
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Weekend Build").waitForExistence(timeout: 5))
        settle()
    }

    @MainActor
    private func addCard(_ app: XCUIApplication, cardID: String, toList listName: String) throws {
        let searchButton = firstElement(app, identifier: "search-sidebar-button")
        if searchButton.waitForExistence(timeout: 2) {
            searchButton.click()
            settle()
        }

        XCTAssertTrue(firstElement(app, identifier: "open-card-\(cardID)").waitForExistence(timeout: 5))
        let addButton = firstElement(app, identifier: "add-card-to-list-\(cardID)")
        if addButton.waitForExistence(timeout: 2) {
            addButton.click()
        } else {
            firstElement(app, identifier: "open-card-\(cardID)")
                .coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.08))
                .click()
        }

        let identifiedMenuItem = firstElement(app, identifier: "add-card-\(cardID)-to-list-\(listName)")
        if identifiedMenuItem.waitForExistence(timeout: 2) {
            identifiedMenuItem.click()
            settle()
            return
        }

        let namedMenuItem = app.menuItems[listName]
        if namedMenuItem.waitForExistence(timeout: 2) {
            namedMenuItem.click()
            settle()
            return
        }

        let namedButton = app.buttons[listName]
        XCTAssertTrue(namedButton.waitForExistence(timeout: 2))
        namedButton.click()
        settle()
    }

    @MainActor
    private func settle(_ interval: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}

private enum MacScreenshotFixture {
    static func fixtureCardsJSON() throws -> String {
        let data = try JSONEncoder().encode(fixtureCards())
        return String(decoding: data, as: UTF8.self)
    }

    static func fixtureCards() -> [CardRecord] {
        definitions.enumerated().map { index, definition in
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
                illustrationCount: 1
            )
        }
    }

    private static func writeArtwork(to url: URL, palette: MacArtworkPalette, seed: Int) throws {
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
            throw MacScreenshotFixtureError.imageContextFailed
        }

        context.setFillColor(palette.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var random = MacSeededRandom(seed: UInt64(seed))

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
            throw MacScreenshotFixtureError.imageContextFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MacScreenshotFixtureError.imageWriteFailed
        }
    }

    private static let definitions: [MacCardDefinition] = [
        MacCardDefinition(id: "astral-archivist", name: "Astral Archivist", kind: "Scholar", setName: "Aurora Catalog", code: "ARC", releaseDate: "2026-01-03", rarity: "rare", cost: "3", text: "Catalog two discoveries. Preserve one note in your collection.", price: 2.40, keywords: ["Catalog"], palette: MacArtworkPalette("#0c214a", "#7aa8ff", "#6a52ff", "#d7e6ff", "#7ca7d8")),
        MacCardDefinition(id: "harbor-lantern", name: "Harbor Lantern", kind: "Relic", setName: "Tidefoundry", code: "TDF", releaseDate: "2026-01-10", rarity: "uncommon", cost: "2", text: "Charge once. Add a color from your saved palette.", price: 0.85, keywords: ["Charge"], palette: MacArtworkPalette("#0d3a3a", "#5bd0ce", "#f0d35c", "#e9fffb", "#7cc8c8")),
        MacCardDefinition(id: "copperbound-surveyor", name: "Copperbound Surveyor", kind: "Construct", setName: "Brass Garden", code: "BRG", releaseDate: "2026-02-01", rarity: "rare", cost: "4", text: "When this enters, inspect the top entry of any list.", price: 4.10, keywords: ["Inspect"], palette: MacArtworkPalette("#4d211b", "#f08a5d", "#f6dc62", "#ffe5d4", "#b36a50")),
        MacCardDefinition(id: "mistvale-gate", name: "Mistvale Gate", kind: "Landmark", setName: "Cloudline", code: "CLD", releaseDate: "2026-02-12", rarity: "common", cost: "", text: "Open a path. Mark one item as ready.", price: 1.20, keywords: ["Open"], palette: MacArtworkPalette("#10334a", "#a8dadc", "#457b9d", "#f0fbff", "#7eaac6")),
        MacCardDefinition(id: "quartz-drake", name: "Quartz Drake", kind: "Creature", setName: "Glass Peaks", code: "GLS", releaseDate: "2026-03-05", rarity: "mythic", cost: "5", text: "Glide. Whenever you sort a list, this gains clarity.", price: 7.30, keywords: ["Glide"], palette: MacArtworkPalette("#27283d", "#f8f7ff", "#b8c0ff", "#ffffff", "#bfc5e8")),
        MacCardDefinition(id: "verdant-compass", name: "Verdant Compass", kind: "Tool", setName: "Mosswork", code: "MSW", releaseDate: "2026-03-20", rarity: "uncommon", cost: "1", text: "Tap to find a category. If it is empty, create a new one.", price: 0.55, keywords: ["Tap"], palette: MacArtworkPalette("#14351f", "#8ac926", "#198754", "#ecffd9", "#70a85b"))
    ]
}

private struct MacCardDefinition {
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
    var palette: MacArtworkPalette
}

private struct MacArtworkPalette {
    var background: MacRGBColor
    var primary: MacRGBColor
    var secondary: MacRGBColor
    var highlight: MacRGBColor
    var line: MacRGBColor

    init(_ background: String, _ primary: String, _ secondary: String, _ highlight: String, _ line: String) {
        self.background = MacRGBColor(hex: background)
        self.primary = MacRGBColor(hex: primary)
        self.secondary = MacRGBColor(hex: secondary)
        self.highlight = MacRGBColor(hex: highlight)
        self.line = MacRGBColor(hex: line)
    }
}

private struct MacRGBColor {
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

private struct MacSeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state % UInt64(max(1, upperBound)))
    }
}

private enum MacScreenshotFixtureError: Error {
    case imageContextFailed
    case imageWriteFailed
}

private enum MacScreenshotPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let sortMode = "Grimora.defaultSearch.sortMode"
    static let sortDirection = "Grimora.defaultSearch.sortDirection"
    static let searchInputMode = "Grimora.search.inputMode"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
