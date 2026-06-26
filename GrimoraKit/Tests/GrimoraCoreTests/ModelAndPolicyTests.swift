@testable import GrimoraCore
import XCTest

final class ModelAndPolicyTests: XCTestCase {
    func testSortTitlesAndIdentifiersAreStable() {
        XCTAssertEqual(SortMode.allCases.map(\.id), [
            "name", "releaseDate", "setNumber", "rarity", "color", "priceUSD", "priceTIX",
            "priceEUR", "manaValue", "power", "toughness", "artistName", "edhrecRank",
            "pennyRank"
        ])
        XCTAssertEqual(SortMode.allCases.map(\.title), [
            "Name", "Release Date", "Set/Number", "Rarity", "Color", "Price: USD", "Price: TIX",
            "Price: EUR", "Mana Value", "Power", "Toughness", "Artist Name", "EDHREC Rank",
            "Penny Rank"
        ])
    }

    func testCardCollectionRulesetsExposeAllowedZonesAndNormalizeInvalidZones() {
        XCTAssertEqual(CardCollectionRuleset.commander.allowedZones, [.commander, .mainboard, .maybeboard])
        XCTAssertEqual(CardCollectionRuleset.modern.allowedZones, [.mainboard, .sideboard, .maybeboard])
        XCTAssertEqual(CardCollectionRuleset.none.allowedZones, [.mainboard, .maybeboard])

        XCTAssertEqual(CardCollectionRuleset.commander.normalizedZone(.sideboard), .mainboard)
        XCTAssertEqual(CardCollectionRuleset.modern.normalizedZone(.commander), .mainboard)
        XCTAssertEqual(CardCollectionRuleset.none.normalizedZone(.sideboard), .mainboard)
        XCTAssertEqual(CardCollectionRuleset.commander.normalizedZone(.maybeboard), .maybeboard)
    }

    func testCardImageFallbacksPreferExpectedPaths() {
        let face = CardFaceRecord(
            cardID: "card",
            faceIndex: 0,
            name: "Face",
            typeLine: "Instant",
            oracleText: "Text",
            normalImagePath: "/face-normal.jpg",
            largeImagePath: "/face-large.jpg"
        )
        let faceOnly = CardRecord(
            id: "card",
            name: "Card",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "modal_dfc",
            typeLine: "",
            oracleText: "",
            faces: [face]
        )
        XCTAssertEqual(faceOnly.displayImagePath, "/face-normal.jpg")
        XCTAssertEqual(faceOnly.detailImagePath, "/face-large.jpg")

        var front = faceOnly
        front.normalImagePath = "/front-normal.jpg"
        front.largeImagePath = "/front-large.jpg"
        XCTAssertEqual(front.displayImagePath, "/front-normal.jpg")
        XCTAssertEqual(front.detailImagePath, "/front-large.jpg")

        var largeOnly = front
        largeOnly.normalImagePath = nil
        largeOnly.smallImagePath = nil
        largeOnly.faces = []
        XCTAssertEqual(largeOnly.displayImagePath, "/front-large.jpg")

        var smallAndLarge = largeOnly
        smallAndLarge.smallImagePath = "/front-small.jpg"
        XCTAssertEqual(smallAndLarge.displayImagePath, "/front-large.jpg")
    }

    func testArtworkPresentationExposesTransformFaces() {
        let card = CardRecord(
            id: "fable",
            name: "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki",
            setCode: "neo",
            setName: "Kamigawa: Neon Dynasty",
            setType: "expansion",
            collectorNumber: "141",
            rarity: "rare",
            colorSortKey: 1,
            layout: "transform",
            typeLine: "Enchantment — Saga // Enchantment Creature",
            oracleText: "",
            faces: [
                CardFaceRecord(
                    cardID: "fable",
                    faceIndex: 0,
                    name: "Fable of the Mirror-Breaker",
                    typeLine: "Enchantment — Saga",
                    oracleText: "",
                    normalImagePath: "/fable-front.jpg"
                ),
                CardFaceRecord(
                    cardID: "fable",
                    faceIndex: 1,
                    name: "Reflection of Kiki-Jiki",
                    typeLine: "Enchantment Creature — Goblin Shaman",
                    oracleText: "",
                    normalImagePath: "/fable-back.jpg"
                )
            ]
        )

        let variants = CardArtworkPresentationResolver.variants(for: card)

        XCTAssertEqual(variants.map(\.title), [
            "Fable of the Mirror-Breaker",
            "Reflection of Kiki-Jiki"
        ])
        XCTAssertEqual(variants.map(\.rotation), [.none, .none])
        XCTAssertEqual(variants.map(\.imagePath), ["/fable-front.jpg", "/fable-back.jpg"])
    }

    func testArtworkPresentationRotatesSplitFuseAndAftermathClockwise() {
        for (layout, keywords, typeLine) in [
            ("split", ["Fuse"], "Instant // Instant"),
            ("split", ["Aftermath"], "Sorcery // Sorcery")
        ] {
            let card = CardRecord(
                id: "\(typeLine)-\(keywords.joined())",
                name: "Wax // Wane",
                setCode: "set",
                setName: "Set",
                setType: "expansion",
                collectorNumber: "1",
                rarity: "uncommon",
                colorSortKey: 0,
                layout: layout,
                typeLine: typeLine,
                oracleText: "",
                keywords: keywords,
                normalImagePath: "/split.jpg"
            )

            let variants = CardArtworkPresentationResolver.variants(for: card)

            XCTAssertEqual(variants.map(\.rotation), [.none, .clockwise90])
            XCTAssertEqual(variants.map(\.imagePath), ["/split.jpg", "/split.jpg"])
        }
    }

    func testArtworkPresentationDefaultsRoomsToRotatedArtwork() {
        let card = CardRecord(
            id: "room",
            name: "Dollmaker's Shop // Porcelain Gallery",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "split",
            typeLine: "Enchantment — Room // Enchantment — Room",
            oracleText: "",
            normalImagePath: "/room.jpg"
        )

        let variants = CardArtworkPresentationResolver.variants(for: card)

        XCTAssertEqual(variants.map(\.id), ["card-rotation-90"])
        XCTAssertEqual(variants.map(\.rotation), [.clockwise90])
        XCTAssertEqual(variants.map(\.imagePath), ["/room.jpg"])
    }

    func testArtworkPresentationRotatesBattleFrontAndStillShowsBackFace() {
        let card = CardRecord(
            id: "battle",
            name: "Invasion of Tolvada // The Broken Sky",
            setCode: "mom",
            setName: "March of the Machine",
            setType: "expansion",
            collectorNumber: "241",
            rarity: "rare",
            colorSortKey: 0,
            layout: "transform",
            typeLine: "Battle — Siege // Enchantment",
            oracleText: "",
            faces: [
                CardFaceRecord(
                    cardID: "battle",
                    faceIndex: 0,
                    name: "Invasion of Tolvada",
                    typeLine: "Battle — Siege",
                    oracleText: "",
                    normalImagePath: "/battle-front.jpg"
                ),
                CardFaceRecord(
                    cardID: "battle",
                    faceIndex: 1,
                    name: "The Broken Sky",
                    typeLine: "Enchantment",
                    oracleText: "",
                    normalImagePath: "/battle-back.jpg"
                )
            ]
        )

        let variants = CardArtworkPresentationResolver.variants(for: card)

        XCTAssertEqual(variants.map(\.id), [
            "face-0-rotation-90",
            "face-1-rotation-0"
        ])
        XCTAssertEqual(variants.map(\.title), [
            "Invasion of Tolvada",
            "The Broken Sky"
        ])
        XCTAssertEqual(variants.map(\.rotation), [.clockwise90, .none])
        XCTAssertEqual(variants.map(\.imagePath), [
            "/battle-front.jpg",
            "/battle-back.jpg"
        ])
    }

    func testArtworkPresentationRotatesFlipCardsUpsideDown() {
        let card = CardRecord(
            id: "budoka",
            name: "Budoka Gardener // Dokai, Weaver of Life",
            setCode: "chk",
            setName: "Champions of Kamigawa",
            setType: "expansion",
            collectorNumber: "202",
            rarity: "rare",
            colorSortKey: 4,
            layout: "flip",
            typeLine: "Creature — Human Monk // Legendary Creature — Human Monk",
            oracleText: "",
            normalImagePath: "/budoka.jpg"
        )

        let variants = CardArtworkPresentationResolver.variants(for: card)

        XCTAssertEqual(variants.map(\.rotation), [.none, .upsideDown180])
        XCTAssertEqual(variants.map(\.imagePath), ["/budoka.jpg", "/budoka.jpg"])
    }

    func testArtworkPresentationRotatesLandscapeLayoutsAndIntrinsicLandscapeFallback() {
        for layout in ["planar", "scheme", "vanguard"] {
            let card = CardRecord(
                id: layout,
                name: "Landscape Card",
                setCode: "set",
                setName: "Set",
                setType: "funny",
                collectorNumber: "1",
                rarity: "rare",
                colorSortKey: 0,
                layout: layout,
                typeLine: "Plane",
                oracleText: "",
                normalImagePath: "/landscape-\(layout).jpg"
            )

            XCTAssertEqual(
                CardArtworkPresentationResolver.variants(for: card).map(\.rotation),
                [.none, .clockwise90]
            )
        }

        let oddball = CardRecord(
            id: "oddball",
            name: "Oddball",
            setCode: "set",
            setName: "Set",
            setType: "funny",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Artifact",
            oracleText: "",
            normalImagePath: "/oddball.jpg"
        )

        XCTAssertEqual(
            CardArtworkPresentationResolver.variants(for: oddball).map(\.rotation),
            [.none]
        )
        XCTAssertEqual(
            CardArtworkPresentationResolver.variants(
                for: oddball,
                includesLandscapeRotation: true
            ).map(\.rotation),
            [.none, .clockwise90]
        )
    }

    func testArtworkPresentationDoesNotRotateOrdinaryLayouts() {
        for layout in ["normal", "adventure", "class", "case", "leveler", "prototype", "mutate", "saga"] {
            let card = CardRecord(
                id: layout,
                name: "Ordinary \(layout)",
                setCode: "set",
                setName: "Set",
                setType: "expansion",
                collectorNumber: "1",
                rarity: "common",
                colorSortKey: 0,
                layout: layout,
                typeLine: "Creature",
                oracleText: "",
                normalImagePath: "/\(layout).jpg"
            )

            XCTAssertEqual(
                CardArtworkPresentationResolver.variants(for: card).map(\.rotation),
                [.none],
                "Expected \(layout) not to rotate by layout alone"
            )
        }
    }

    func testArtworkMotionClassifiesSameArtworkRotation() {
        let normal = artworkVariant(
            id: "card-rotation-0",
            source: .card,
            imagePath: "/wax.jpg",
            rotation: .none
        )
        let rotated = artworkVariant(
            id: "card-rotation-90",
            source: .card,
            imagePath: "/wax.jpg",
            rotation: .clockwise90
        )

        let plan = CardArtworkMotionPlan.transition(from: normal, to: rotated)

        XCTAssertEqual(plan.kind, .rotate)
        XCTAssertEqual(plan.rotationDeltaDegrees, 90)
        XCTAssertEqual(plan.targetRotationDegrees, 90)
    }

    func testArtworkMotionClassifiesDifferentFaceAsFlip() {
        let front = artworkVariant(
            id: "face-0-rotation-0",
            source: .face(0),
            imagePath: "/fable-front.jpg",
            rotation: .none
        )
        let back = artworkVariant(
            id: "face-1-rotation-0",
            source: .face(1),
            imagePath: "/fable-back.jpg",
            rotation: .none
        )

        let plan = CardArtworkMotionPlan.transition(from: front, to: back)

        XCTAssertEqual(plan.kind, .flip)
        XCTAssertEqual(plan.rotationDeltaDegrees, 0)
        XCTAssertEqual(plan.targetRotationDegrees, 0)
    }

    func testArtworkMotionClassifiesBattleRotationThenBackFace() {
        let front = artworkVariant(
            id: "face-0-rotation-0",
            source: .face(0),
            imagePath: "/battle-front.jpg",
            rotation: .none
        )
        let rotatedFront = artworkVariant(
            id: "face-0-rotation-90",
            source: .face(0),
            imagePath: "/battle-front.jpg",
            rotation: .clockwise90
        )
        let back = artworkVariant(
            id: "face-1-rotation-0",
            source: .face(1),
            imagePath: "/battle-back.jpg",
            rotation: .none
        )

        XCTAssertEqual(CardArtworkMotionPlan.transition(from: front, to: rotatedFront).kind, .rotate)
        XCTAssertEqual(CardArtworkMotionPlan.transition(from: rotatedFront, to: back).kind, .flip)
    }

    func testArtworkMotionUsesShortestReverseRotation() {
        let normal = artworkVariant(
            id: "card-rotation-0",
            source: .card,
            imagePath: "/card.jpg",
            rotation: .none
        )
        let sideways = artworkVariant(
            id: "card-rotation-90",
            source: .card,
            imagePath: "/card.jpg",
            rotation: .clockwise90
        )
        let upsideDown = artworkVariant(
            id: "card-rotation-180",
            source: .card,
            imagePath: "/card.jpg",
            rotation: .upsideDown180
        )

        let sidewaysPlan = CardArtworkMotionPlan.transition(from: sideways, to: normal)
        let upsideDownPlan = CardArtworkMotionPlan.transition(from: upsideDown, to: normal)

        XCTAssertEqual(sidewaysPlan.kind, .rotate)
        XCTAssertEqual(sidewaysPlan.rotationDeltaDegrees, -90)
        XCTAssertEqual(upsideDownPlan.kind, .rotate)
        XCTAssertEqual(abs(upsideDownPlan.rotationDeltaDegrees), 180)
    }

    func testLargeCachedImageCanDisplayWithoutSatisfyingPreviewCache() {
        let card = CardRecord(
            id: "card",
            name: "Card",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Instant",
            oracleText: "",
            largeImagePath: "/tmp/card-large.jpg",
            smallImageURL: "https://example.test/card-small.jpg"
        )

        XCTAssertEqual(card.existingDisplayImagePath, "/tmp/card-large.jpg")
        XCTAssertTrue(card.hasExistingDisplayImage)
        XCTAssertFalse(card.hasCachedDisplayImage(for: .small))
    }

    func testMissingCachedDisplayImageFileDetectsStaleAbsolutePaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let existingImage = directory.appendingPathComponent("existing.jpg")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Fixtures.imageData().write(to: existingImage, options: .atomic)

        let stalePreview = CardRecord(
            id: "card",
            name: "Card",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Instant",
            oracleText: "",
            smallImagePath: directory.appendingPathComponent("missing.jpg").path,
            smallImageURL: "https://example.test/card-small.jpg"
        )
        XCTAssertTrue(stalePreview.hasCachedDisplayImage(for: .small))
        XCTAssertTrue(stalePreview.hasMissingCachedDisplayImageFile(for: .small))

        var existingPreview = stalePreview
        existingPreview.smallImagePath = existingImage.path
        XCTAssertFalse(existingPreview.hasMissingCachedDisplayImageFile(for: .small))
    }

    func testBlockingNetworkClientRejectsEveryPurpose() async {
        let client = BlockingNetworkClient()
        let url = URL(string: "https://example.test/file.json")!

        for purpose in [NetworkPurpose.manifestCheck, .bulkDownload, .imageDownload, .deckImport, .priceHistoryDownload] {
            do {
                _ = try await client.data(from: url, purpose: purpose)
                XCTFail("Expected data request to be blocked")
            } catch NetworkClientError.blocked(let blockedPurpose, let blockedURL) {
                XCTAssertEqual(blockedPurpose, purpose)
                XCTAssertEqual(blockedURL, url)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            do {
                try await client.download(from: url, to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), purpose: purpose)
                XCTFail("Expected download to be blocked")
            } catch NetworkClientError.blocked(let blockedPurpose, let blockedURL) {
                XCTAssertEqual(blockedPurpose, purpose)
                XCTAssertEqual(blockedURL, url)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSQLiteErrorsAndRollbackAreSurfaced() throws {
        let database = try SQLiteDatabase(storage: .inMemory)
        XCTAssertThrowsError(try database.prepare("SELECT * FROM missing_table"))
        XCTAssertThrowsError(try database.execute("definitely not sql"))

        try database.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY)")
        XCTAssertThrowsError(try database.transaction {
            try database.execute("INSERT INTO sample (id) VALUES (1)")
            throw SQLiteError.executionFailed("forced rollback")
        })

        let statement = try database.prepare("SELECT COUNT(*) FROM sample")
        _ = try statement.step()
        XCTAssertEqual(statement.int(at: 0), 0)
    }

    private func artworkVariant(
        id: String,
        source: CardArtworkSourceReference,
        imagePath: String,
        rotation: CardArtworkRotation
    ) -> CardArtworkVariant {
        CardArtworkVariant(
            id: id,
            source: source,
            title: "Card",
            typeLine: "Type",
            imagePath: imagePath,
            hasRemoteImage: false,
            rotation: rotation
        )
    }
}
