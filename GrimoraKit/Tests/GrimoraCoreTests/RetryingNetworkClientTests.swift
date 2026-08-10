@testable import GrimoraCore
import XCTest

/// Covers the retry behaviour added after the Aug 2026 outage, where scheduled runs died on
/// `-1001`/`-1009` because the Mac suspended underneath them. The rules that matter: transient
/// URLErrors are retried, everything else fails fast, and a retried download must not be left
/// half-written.
final class RetryingNetworkClientTests: XCTestCase {
    private let url = URL(string: "https://example.test/artifact.jsonl.gz")!

    func testRetriesTransientFailureThenSucceeds() async throws {
        let flaky = FlakyNetworkClient(
            failures: [URLError(.timedOut), URLError(.notConnectedToInternet)],
            payload: Data("ok".utf8)
        )
        let client = RetryingNetworkClient(
            wrapping: flaky,
            maxAttempts: 4,
            initialDelay: .milliseconds(1)
        )

        let data = try await client.data(from: url, purpose: .manifestCheck)

        let attempts = await flaky.attempts()
        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual(attempts, 3, "should have failed twice then succeeded")
    }

    func testGivesUpAfterMaxAttempts() async throws {
        let flaky = FlakyNetworkClient(
            failures: Array(repeating: URLError(.timedOut), count: 10),
            payload: Data()
        )
        let client = RetryingNetworkClient(
            wrapping: flaky,
            maxAttempts: 3,
            initialDelay: .milliseconds(1)
        )

        do {
            _ = try await client.data(from: url, purpose: .manifestCheck)
            XCTFail("Expected the final failure to propagate")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
        let attempts = await flaky.attempts()
        XCTAssertEqual(attempts, 3, "should stop at maxAttempts, not keep going")
    }

    func testDoesNotRetryNonTransientFailure() async throws {
        let flaky = FlakyNetworkClient(
            failures: [NetworkClientError.badHTTPStatus(404)],
            payload: Data("unreachable".utf8)
        )
        let client = RetryingNetworkClient(
            wrapping: flaky,
            maxAttempts: 4,
            initialDelay: .milliseconds(1)
        )

        do {
            _ = try await client.data(from: url, purpose: .manifestCheck)
            XCTFail("Expected a bad status to fail immediately")
        } catch NetworkClientError.badHTTPStatus(let code) {
            XCTAssertEqual(code, 404)
        }
        let attempts = await flaky.attempts()
        XCTAssertEqual(attempts, 1, "a 404 must not burn the retry budget")
    }

    func testRetriedDownloadLeavesCompleteFile() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }

        let payload = Data(repeating: 0xAB, count: 4096)
        let flaky = FlakyNetworkClient(failures: [URLError(.networkConnectionLost)], payload: payload)
        let client = RetryingNetworkClient(
            wrapping: flaky,
            maxAttempts: 3,
            initialDelay: .milliseconds(1)
        )

        try await client.download(from: url, to: destination, purpose: .bulkDownload, progress: nil)

        let attempts = await flaky.attempts()
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(attempts, 2)
    }

    func testTransientClassification() {
        XCTAssertTrue(RetryingNetworkClient.isTransient(URLError(.timedOut)))
        XCTAssertTrue(RetryingNetworkClient.isTransient(URLError(.notConnectedToInternet)))
        XCTAssertTrue(RetryingNetworkClient.isTransient(URLError(.networkConnectionLost)))
        XCTAssertFalse(RetryingNetworkClient.isTransient(URLError(.badURL)))
        XCTAssertFalse(RetryingNetworkClient.isTransient(NetworkClientError.badHTTPStatus(500)))
    }
}

/// Fails with each queued error in turn, then serves `payload`.
private actor FlakyNetworkClient: NetworkClient {
    private var pendingFailures: [any Error]
    private let payload: Data
    private var attemptCount = 0

    init(failures: [any Error], payload: Data) {
        pendingFailures = failures
        self.payload = payload
    }

    func attempts() -> Int { attemptCount }

    private func nextPayload() throws -> Data {
        attemptCount += 1
        if !pendingFailures.isEmpty {
            throw pendingFailures.removeFirst()
        }
        return payload
    }

    func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
        try nextPayload()
    }

    func download(
        from url: URL,
        to destination: URL,
        purpose: NetworkPurpose,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)?
    ) async throws {
        let data = try nextPayload()
        try data.write(to: destination, options: .atomic)
    }
}
