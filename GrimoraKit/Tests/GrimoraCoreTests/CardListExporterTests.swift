@testable import GrimoraCore
import XCTest

final class CardListExporterTests: XCTestCase {
    func testTextExportAggregatesDuplicatePrintsAndHonorsPrintOptions() {
        let bolt = testCard(
            id: "bolt-print",
            name: "Lightning Bolt",
            setCode: "clu",
            collectorNumber: "141"
        )
        let mdfc = testCard(
            id: "bala-ged",
            name: "Bala Ged Recovery // Bala Ged Sanctuary",
            setCode: "znr",
            collectorNumber: "180",
            layout: "modal_dfc",
            faces: [
                CardFaceRecord(
                    cardID: "bala-ged",
                    faceIndex: 0,
                    name: "Bala Ged Recovery",
                    typeLine: "Sorcery",
                    oracleText: "Return target card."
                )
            ]
        )
        let entries = [
            testEntry(card: bolt, position: 0, quantity: 2),
            testEntry(card: mdfc, position: 2),
        ]

        var configuration = CardListExportConfiguration(format: .text)
        configuration.textUsesFrontNameOnlyForMDFC = true

        let result = CardListExporter.export(
            list: testList(),
            entries: entries,
            configuration: configuration
        )

        XCTAssertEqual(
            result.content,
            """
            2x Lightning Bolt (clu) 141
            1x Bala Ged Recovery (znr) 180
            """
        )
        XCTAssertEqual(result.selectedCardCount, 3)
        XCTAssertEqual(result.uniqueCardCount, 2)

        configuration.textIncludesXInQuantity = false
        configuration.textIncludesSetCode = false
        configuration.textIncludesCollectorNumber = false

        let compactResult = CardListExporter.export(
            list: testList(),
            entries: entries,
            configuration: configuration
        )

        XCTAssertEqual(
            compactResult.content,
            """
            2 Lightning Bolt
            1 Bala Ged Recovery
            """
        )
    }

    func testTextExportSupportsGenericAndCardTypeSectionHeaders() {
        let creature = testCard(id: "creature", name: "Elvish Mystic", typeLine: "Creature - Elf")
        let instant = testCard(id: "instant", name: "Counterspell", typeLine: "Instant")
        let land = testCard(id: "land", name: "Island", typeLine: "Basic Land - Island")
        let entries = [
            testEntry(card: instant, position: 0),
            testEntry(card: creature, position: 1),
            testEntry(card: land, position: 2),
        ]

        var configuration = CardListExportConfiguration(format: .text)
        configuration.textSectionHeader = .generic

        let genericResult = CardListExporter.export(
            list: testList(),
            entries: entries,
            configuration: configuration
        )
        XCTAssertTrue(genericResult.content?.hasPrefix("Mainboard\n") == true)

        configuration.textSectionHeader = .cardType
        let cardTypeResult = CardListExporter.export(
            list: testList(),
            entries: entries,
            configuration: configuration
        )

        XCTAssertEqual(
            cardTypeResult.content,
            """
            Creatures
            1x Elvish Mystic (tst) 1

            Instants
            1x Counterspell (tst) 1

            Lands
            1x Island (tst) 1
            """
        )
    }

    func testCSVExportEscapesSelectedColumnsAndMissingValues() {
        let card = testCard(
            id: "alela",
            name: "Alela, Artful Provocateur",
            setName: "Throne of Eldraine",
            manaValue: nil,
            oracleText: "Create a \"Faerie\"\nThen fly.",
            priceUSD: nil
        )
        var configuration = CardListExportConfiguration(format: .csv)
        configuration.csvColumns = [.quantity, .name, .setName, .price, .manaValue, .cardText, .scryfallID]
        configuration.csvIncludesHeaderRow = true

        let result = CardListExporter.export(
            list: testList(),
            entries: [testEntry(card: card, position: 0)],
            configuration: configuration
        )

        XCTAssertEqual(
            result.content,
            """
            Quantity,Name,Set name,Price,Mana value,Card text,Scryfall ID
            1,"Alela, Artful Provocateur",Throne of Eldraine,,,"Create a ""Faerie""
            Then fly.",alela
            """
        )
    }

    func testArenaAndMTGOExportsReportUnavailablePrintsAndFallbacks() {
        let arenaCard = testCard(
            id: "arena-card",
            name: "Arena Card",
            setCode: "ybro",
            collectorNumber: "12",
            games: ["paper", "arena"],
            mtgoID: 99123
        )
        let paperCard = testCard(
            id: "paper-card",
            name: "Paper Card",
            games: ["paper"]
        )
        let entries = [
            testEntry(card: arenaCard, position: 0),
            testEntry(card: paperCard, position: 1),
        ]

        let arenaResult = CardListExporter.export(
            list: testList(),
            entries: entries,
            configuration: CardListExportConfiguration(format: .arena)
        )

        XCTAssertEqual(
            arenaResult.content,
            """
            Deck
            1 Arena Card (YBRO) 12
            """
        )
        XCTAssertTrue(arenaResult.warnings.contains("Skipped Paper Card because it is not marked as available on Arena."))
        XCTAssertFalse(arenaResult.isDownloadable)

        let mtgoResult = CardListExporter.export(
            list: testList(),
            entries: entries,
            configuration: CardListExportConfiguration(format: .mtgoDek)
        )

        XCTAssertTrue(mtgoResult.content?.contains(#"CatID="99123""#) == true)
        XCTAssertTrue(mtgoResult.content?.contains(#"Name="Paper Card""#) == true)
        XCTAssertTrue(mtgoResult.warnings.contains("Paper Card does not have an MTGO ID yet; exported by name only."))
        XCTAssertTrue(mtgoResult.isDownloadable)
    }

    func testDeckRegistrationPDFProducesDataAndSortedPreview() throws {
        let cheap = testCard(id: "cheap", name: "Cheap Spell", manaValue: 1)
        let expensive = testCard(id: "expensive", name: "Expensive Spell", manaValue: 5)
        var configuration = CardListExportConfiguration(format: .deckRegistrationPDF)
        configuration.deckRegistrationFields = CardListDeckRegistrationFields(
            deckName: "League Night",
            date: "2026-04-26",
            firstName: "Sam",
            lastName: "Wagner",
            designer: "Sam",
            dciNumber: "1234",
            location: "Brisbane",
            eventName: "Testing"
        )
        configuration.deckRegistrationSortMode = .manaValue

        let result = CardListExporter.export(
            list: testList(),
            entries: [
                testEntry(card: expensive, position: 0),
                testEntry(card: cheap, position: 1),
            ],
            configuration: configuration,
            date: Date(timeIntervalSince1970: 0)
        )

        let data = try XCTUnwrap(result.data)
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(String(data: data.prefix(8), encoding: .utf8), "%PDF-1.4")
        XCTAssertLessThan(
            try XCTUnwrap(result.preview.range(of: "1 Cheap Spell")?.lowerBound),
            try XCTUnwrap(result.preview.range(of: "1 Expensive Spell")?.lowerBound)
        )
        XCTAssertFalse(result.isCopyable)
        XCTAssertTrue(result.isDownloadable)
    }

    func testCategoryExportsGroupSupportedFormatsAndWarnForFlatFormats() {
        let bolt = testCard(
            id: "bolt-print",
            name: "Lightning Bolt",
            setCode: "clu",
            collectorNumber: "141",
            games: ["paper", "arena"],
            mtgoID: 123
        )
        let growth = testCard(id: "growth", name: "Rampant Growth")
        let categories = [
            testCategory(id: "ramp", name: "Ramp", position: 0),
            testCategory(id: "removal", name: "Removal", position: 1),
        ]
        let entries = [
            testEntry(card: growth, position: 0),
            testEntry(card: bolt, categoryID: "ramp", position: 1),
            testEntry(card: bolt, categoryID: "ramp", position: 2),
            testEntry(card: bolt, categoryID: "removal", position: 3),
        ]

        let text = CardListExporter.export(
            list: testList(),
            entries: entries,
            categories: categories,
            configuration: CardListExportConfiguration(format: .text)
        )
        XCTAssertEqual(
            text.content,
            """
            Uncategorized
            1x Rampant Growth (tst) 1

            Ramp
            2x Lightning Bolt (clu) 141

            Removal
            1x Lightning Bolt (clu) 141
            """
        )
        XCTAssertEqual(text.selectedCardCount, 4)
        XCTAssertEqual(text.uniqueCardCount, 3)

        var csvConfiguration = CardListExportConfiguration(format: .csv)
        csvConfiguration.csvColumns = [.quantity, .category, .name]
        let csv = CardListExporter.export(
            list: testList(),
            entries: entries,
            categories: categories,
            configuration: csvConfiguration
        )
        XCTAssertEqual(
            csv.content,
            """
            Quantity,Category,Name
            1,Uncategorized,Rampant Growth
            2,Ramp,Lightning Bolt
            1,Removal,Lightning Bolt
            """
        )

        let edhrec = CardListExporter.export(
            list: testList(name: "Naya Box"),
            entries: entries,
            categories: categories,
            configuration: CardListExportConfiguration(format: .edhrecArticle)
        )
        XCTAssertEqual(
            edhrec.content,
            """
            # Naya Box

            ## Uncategorized
            1 Rampant Growth

            ## Ramp
            2 Lightning Bolt

            ## Removal
            1 Lightning Bolt
            """
        )

        let deckRegistration = CardListExporter.export(
            list: testList(),
            entries: entries,
            categories: categories,
            configuration: CardListExportConfiguration(format: .deckRegistrationPDF)
        )
        XCTAssertTrue(deckRegistration.preview.contains("Ramp\n2 Lightning Bolt (CLU) 141"))
        XCTAssertTrue(deckRegistration.preview.contains("Removal\n1 Lightning Bolt (CLU) 141"))

        let arena = CardListExporter.export(
            list: testList(),
            entries: entries,
            categories: categories,
            configuration: CardListExportConfiguration(format: .arena)
        )
        XCTAssertTrue(arena.warnings.contains("Categories were omitted because Arena export is a flat deck format."))
    }

    func testGrimoraArchiveExportPreservesDescriptionCategoriesAndMissingEntries() throws {
        let descriptionData = Data([0x01, 0x02, 0x03])
        let list = testList(
            name: "Notes",
            descriptionRTFDData: descriptionData,
            descriptionPlainText: "Remember this.",
            showsDashboard: false,
            dashboardIncludesLands: true,
            displaySortMode: .edhrecRank,
            displaySortDirection: .descending,
            viewMode: .list,
            ruleset: .commander
        )
        let card = testCard(id: "forest", name: "Alpha Forest")
        let categories = [testCategory(id: "ramp", name: "Ramp", position: 0, zone: .sideboard)]
        let entries = [
            testEntry(card: card, zone: .sideboard, categoryID: "ramp", position: 0),
            CardListEntryRecord(
                id: "missing-entry",
                listID: "list",
                zone: .sideboard,
                categoryID: "ramp",
                cardID: "missing-print",
                position: 1,
                quantity: 3,
                createdAt: Date(timeIntervalSince1970: 1)
            ),
        ]

        let result = CardListExporter.export(
            list: list,
            entries: entries,
            categories: categories,
            configuration: CardListExportConfiguration(format: .grimoraArchive)
        )

        XCTAssertFalse(result.isCopyable)
        XCTAssertTrue(result.isDownloadable)
        XCTAssertEqual(result.filename, "Notes.grimoralist")
        XCTAssertEqual(result.selectedCardCount, 4)
        XCTAssertEqual(result.uniqueCardCount, 2)
        XCTAssertTrue(result.preview.contains("Description: Included"))

        let data = try XCTUnwrap(result.data)
        let archive = try CardListArchiveCoder.decode(data)
        XCTAssertEqual(archive.list.descriptionRTFDData, descriptionData)
        XCTAssertEqual(archive.list.descriptionPlainText, "Remember this.")
        XCTAssertFalse(archive.list.showsDashboard)
        XCTAssertTrue(archive.list.dashboardIncludesLands)
        XCTAssertEqual(archive.list.displaySortMode, .edhrecRank)
        XCTAssertEqual(archive.list.displaySortDirection, .descending)
        XCTAssertEqual(archive.list.viewMode, .list)
        XCTAssertEqual(archive.list.ruleset, .commander)
        XCTAssertEqual(archive.categories.map(\.name), ["Ramp"])
        XCTAssertEqual(archive.categories.map(\.zone), [.sideboard])
        XCTAssertEqual(archive.entries.map(\.cardID), ["forest", "missing-print"])
        XCTAssertEqual(archive.entries.map(\.categoryID), ["ramp", "ramp"])
        XCTAssertEqual(archive.entries.map(\.zone), [.sideboard, .sideboard])
        XCTAssertEqual(archive.entries.map(\.quantity), [1, 3])
    }

    func testGrimoraArchiveDecodesLegacyEntriesWithoutQuantity() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "list": {
                "id": "list",
                "name": "Legacy",
                "descriptionPlainText": "",
                "createdAt": "2026-04-26T00:00:00Z",
                "updatedAt": "2026-04-26T00:00:00Z"
              },
              "categories": [],
              "entries": [
                {
                  "id": "entry",
                  "cardID": "forest",
                  "cardName": "Forest",
                  "position": 0,
                  "createdAt": "2026-04-26T00:00:00Z"
                }
              ]
            }
            """.utf8)

        let archive = try CardListArchiveCoder.decode(data)

        XCTAssertEqual(archive.entries.map(\.quantity), [1])
        XCTAssertEqual(archive.entries.map(\.zone), [.mainboard])
        XCTAssertEqual(archive.list.ruleset, .none)
        XCTAssertFalse(archive.list.showsDashboard)
        XCTAssertFalse(archive.list.dashboardIncludesLands)
        XCTAssertNil(archive.list.displaySortMode)
        XCTAssertEqual(archive.list.displaySortDirection, .ascending)
        XCTAssertEqual(archive.list.viewMode, .grid)
    }

    func testNonArchiveExportsWarnWhenListHasDescription() {
        let list = testList(descriptionPlainText: "Sideboard notes")
        let result = CardListExporter.export(
            list: list,
            entries: [testEntry(card: testCard(id: "bolt", name: "Lightning Bolt"), position: 0)],
            configuration: CardListExportConfiguration(format: .text)
        )

        XCTAssertEqual(result.warnings, ["List descriptions are only preserved by Grimora Archive export."])
    }

    private func testList(
        name: String = "Configuration 101",
        descriptionRTFDData: Data? = nil,
        descriptionPlainText: String = "",
        showsDashboard: Bool = false,
        dashboardIncludesLands: Bool = false,
        displaySortMode: SortMode? = nil,
        displaySortDirection: SearchSortDirection = .ascending,
        viewMode: CardListViewMode = .grid,
        ruleset: CardListRuleset = .none
    ) -> CardListRecord {
        CardListRecord(
            id: "list",
            name: name,
            ruleset: ruleset,
            descriptionRTFDData: descriptionRTFDData,
            descriptionPlainText: descriptionPlainText,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            showsDashboard: showsDashboard,
            dashboardIncludesLands: dashboardIncludesLands,
            displaySortMode: displaySortMode,
            displaySortDirection: displaySortDirection,
            viewMode: viewMode,
            entryCount: 0
        )
    }

    private func testCategory(
        id: String,
        name: String,
        position: Int,
        zone: CardListZone = .mainboard
    ) -> CardListCategoryRecord {
        CardListCategoryRecord(
            id: id,
            listID: "list",
            zone: zone,
            name: name,
            position: position,
            createdAt: Date(timeIntervalSince1970: Double(position)),
            updatedAt: Date(timeIntervalSince1970: Double(position)),
            entryCount: 0
        )
    }

    private func testEntry(
        card: CardRecord,
        zone: CardListZone = .mainboard,
        categoryID: String? = nil,
        position: Int,
        quantity: Int = 1
    ) -> CardListEntryRecord {
        CardListEntryRecord(
            id: "entry-\(position)",
            listID: "list",
            zone: zone,
            categoryID: categoryID,
            cardID: card.id,
            position: position,
            quantity: quantity,
            createdAt: Date(timeIntervalSince1970: Double(position)),
            card: card
        )
    }

    private func testCard(
        id: String,
        name: String,
        setCode: String = "tst",
        setName: String = "Test Set",
        collectorNumber: String = "1",
        layout: String = "normal",
        typeLine: String = "Instant",
        manaValue: Double? = 1,
        oracleText: String = "Test text.",
        games: [String] = ["paper"],
        mtgoID: Int? = nil,
        priceUSD: Double? = 0.25,
        faces: [CardFaceRecord] = []
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: "\(id)-oracle",
            name: name,
            setCode: setCode,
            setName: setName,
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber.prefix { $0.isNumber }),
            rarity: "rare",
            rarityRank: 2,
            mtgoID: mtgoID,
            manaValue: manaValue,
            priceUSD: priceUSD,
            colorSortKey: 0,
            colors: ["U"],
            colorIdentity: ["U"],
            layout: layout,
            typeLine: typeLine,
            oracleText: oracleText,
            games: games,
            isRealCard: true,
            faces: faces
        )
    }
}
