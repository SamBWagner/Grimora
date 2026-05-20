@testable import GrimoraCore
import XCTest

final class ImageStoreTests: XCTestCase {
    func testLocalURLIsStableAndKeepsQualityFaceAndExtension() throws {
        let store = ImageStore(rootDirectory: URL(fileURLWithPath: "/tmp/images"))
        let remote = URL(string: "https://cards.scryfall.io/normal/front/a/a/card.jpg?123")!

        let first = store.localURL(for: remote, cardID: "card-id", faceIndex: 1, quality: "normal")
        let second = store.localURL(for: remote, cardID: "card-id", faceIndex: 1, quality: "normal")

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.path.contains("card-id/face-1"))
        XCTAssertTrue(first.lastPathComponent.hasPrefix("normal-"))
        XCTAssertEqual(first.pathExtension, "jpg")
    }

    func testRemoveAllImagesDeletesContentsAndRecreatesRootDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ImageStore(rootDirectory: directory)
        let nestedImage = directory.appendingPathComponent("card/front/small.jpg")
        try FileManager.default.createDirectory(at: nestedImage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.imageData().write(to: nestedImage)

        try store.removeAllImages()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedImage.path))
    }

    func testDownloadingResolverDownloadsRequestedImageSizesAndReportsFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let normal = URL(string: "https://example.test/normal.jpg")!
        let large = URL(string: "https://example.test/large.jpg")!
        let artCrop = URL(string: "https://example.test/art-crop.jpg")!
        let network = RecordingNetworkClient(
            dataResponses: [
                normal: Fixtures.imageData(),
                artCrop: Fixtures.imageData()
            ],
            errors: [large: NetworkClientError.badHTTPStatus(404)]
        )
        let resolver = DownloadingImageResolver(store: ImageStore(rootDirectory: directory), network: network)

        let result = await resolver.resolve(
            ImageURLPair(normal: normal, large: large, artCrop: artCrop),
            cardID: "card",
            faceIndex: nil
        )

        XCTAssertNotNil(result.paths.normalPath)
        XCTAssertNil(result.paths.largePath)
        XCTAssertNotNil(result.paths.artCropPath)
        XCTAssertEqual(result.failedURLs, [large])
        let requests = await network.requests()
        let purposes = requests.map(\.1)
        XCTAssertEqual(purposes, [.imageDownload, .imageDownload, .imageDownload])
    }

    func testDownloadingResolverCanPredictLocalPathsWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let normal = URL(string: "https://example.test/normal.jpg")!
        let large = URL(string: "https://example.test/large.jpg")!
        let artCrop = URL(string: "https://example.test/art-crop.jpg")!
        let network = RecordingNetworkClient()
        let resolver = DownloadingImageResolver(store: ImageStore(rootDirectory: directory), network: network)

        let paths = resolver.localPaths(
            for: ImageURLPair(normal: normal, large: large, artCrop: artCrop),
            cardID: "card",
            faceIndex: nil
        )

        XCTAssertNotNil(paths.normalPath)
        XCTAssertNotNil(paths.largePath)
        XCTAssertNotNil(paths.artCropPath)
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testSmallImageRequestsDoNotFallbackToLargerPayloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let normal = URL(string: "https://example.test/normal.jpg")!
        let large = URL(string: "https://example.test/large.jpg")!
        let network = RecordingNetworkClient(dataResponses: [
            normal: Fixtures.imageData(),
            large: Fixtures.imageData()
        ])
        let resolver = DownloadingImageResolver(store: ImageStore(rootDirectory: directory), network: network)

        let result = await resolver.resolve(
            ImageURLPair(normal: normal, large: large),
            cardID: "card",
            faceIndex: nil,
            qualities: [.small]
        )

        XCTAssertEqual(result.paths, LocalImagePair())
        XCTAssertEqual(result.failedURLs, [])
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testDownloadingResolverSkipsMissingAndExistingURLs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let normal = URL(string: "https://example.test/existing.jpg")!
        let store = ImageStore(rootDirectory: directory)
        let existing = store.localURL(for: normal, cardID: "card", faceIndex: 0, quality: "normal")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.imageData().write(to: existing)

        let network = RecordingNetworkClient()
        let resolver = DownloadingImageResolver(store: store, network: network)

        let empty = await resolver.resolve(ImageURLPair(normal: nil, large: nil), cardID: "card", faceIndex: nil)
        XCTAssertEqual(empty.paths, LocalImagePair())
        XCTAssertEqual(empty.failedURLs, [])

        let existingResult = await resolver.resolve(ImageURLPair(normal: normal, large: nil), cardID: "card", faceIndex: 0)
        XCTAssertEqual(existingResult.paths.normalPath, existing.path)
        XCTAssertEqual(existingResult.failedURLs, [])
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testDownloadingResolverReplacesUnreadableExistingImageFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let small = URL(string: "https://example.test/corrupt.jpg")!
        let store = ImageStore(rootDirectory: directory)
        let existing = store.localURL(for: small, cardID: "card", faceIndex: nil, quality: "small")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: existing)

        let network = RecordingNetworkClient(dataResponses: [small: Fixtures.imageData()])
        let resolver = DownloadingImageResolver(store: store, network: network)

        let result = await resolver.resolve(
            ImageURLPair(small: small, normal: nil, large: nil),
            cardID: "card",
            faceIndex: nil,
            qualities: [.small]
        )

        XCTAssertEqual(result.paths.smallPath, existing.path)
        XCTAssertEqual(result.failedURLs, [])
        XCTAssertEqual(try Data(contentsOf: existing), Fixtures.imageData())
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.0), [small])
    }
}
