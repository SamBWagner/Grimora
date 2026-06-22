@testable import GrimoraCore
import Foundation
import XCTest

final class CurrencyExchangeRateTests: XCTestCase {
    func testStandardCurrencySuiteIncludesMajorCurrencies() {
        let codes = Set(CardValueDisplayCurrency.allCases.map(\.code))
        for expected in ["USD", "EUR", "GBP", "AUD", "CAD", "JPY"] {
            XCTAssertTrue(codes.contains(expected), "Missing currency \(expected)")
        }
    }

    func testEachCurrencyExposesCodeNameAndTitle() {
        for currency in CardValueDisplayCurrency.allCases {
            XCTAssertEqual(currency.code, currency.rawValue)
            XCTAssertFalse(currency.name.isEmpty)
            XCTAssertEqual(currency.title, "\(currency.name) (\(currency.code))")
        }
    }

    func testFrankfurterClientDecodesLatestUSDToEURRate() async throws {
        let url = FrankfurterCurrencyExchangeRateClient.latestRateURL(from: .usd, to: .eur)
        let network = RecordingNetworkClient(dataResponses: [
            url: Data("""
            [
              {"date": "2026-05-19", "base": "USD", "quote": "EUR", "rate": 0.9213}
            ]
            """.utf8)
        ])
        let client = FrankfurterCurrencyExchangeRateClient(network: network)

        let rate = try await client.latestRate(from: .usd, to: .eur)

        XCTAssertEqual(
            rate,
            CurrencyExchangeRate(
                baseCurrency: .usd,
                quoteCurrency: .eur,
                rate: 0.9213,
                date: "2026-05-19",
                providerName: "Frankfurter"
            )
        )
        XCTAssertEqual(url.query?.contains("quotes=EUR"), true)
    }

    func testFrankfurterClientDecodesLatestUSDToAUDRate() async throws {
        let url = FrankfurterCurrencyExchangeRateClient.latestRateURL(from: .usd, to: .aud)
        let network = RecordingNetworkClient(dataResponses: [
            url: Data("""
            [
              {"date": "2026-05-19", "base": "USD", "quote": "AUD", "rate": 1.3996}
            ]
            """.utf8)
        ])
        let client = FrankfurterCurrencyExchangeRateClient(network: network)

        let rate = try await client.latestRate(from: .usd, to: .aud)

        XCTAssertEqual(
            rate,
            CurrencyExchangeRate(
                baseCurrency: .usd,
                quoteCurrency: .aud,
                rate: 1.3996,
                date: "2026-05-19",
                providerName: "Frankfurter"
            )
        )
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.0), [url])
        XCTAssertEqual(requests.map(\.1), [.priceHistoryDownload])
    }

    func testCachedCurrencyExchangeRateClientSavesLiveRateAndReusesSameDayCache() async throws {
        let userDefaults = try isolatedUserDefaults()
        let date = try XCTUnwrap(Self.utcDate(year: 2026, month: 5, day: 19))
        let liveRate = CurrencyExchangeRate(
            baseCurrency: .usd,
            quoteCurrency: .aud,
            rate: 1.5,
            date: "2026-05-19",
            providerName: "Frankfurter"
        )
        let liveClient = CachedCurrencyExchangeRateClient(
            liveClient: FixedExchangeRateClient(rate: liveRate),
            userDefaults: userDefaults,
            now: { date }
        )

        let fetchedLiveRate = try await liveClient.latestRate(from: .usd, to: .aud)
        XCTAssertEqual(fetchedLiveRate, liveRate)
        XCTAssertEqual(
            CachedCurrencyExchangeRateClient.cachedRate(from: .usd, to: .aud, userDefaults: userDefaults),
            liveRate
        )

        let cachedClient = CachedCurrencyExchangeRateClient(
            liveClient: ThrowingExchangeRateClient(),
            userDefaults: userDefaults,
            now: { date }
        )
        let fetchedCachedRate = try await cachedClient.latestRate(from: .usd, to: .aud)
        XCTAssertEqual(fetchedCachedRate, liveRate)
    }

    func testCachedCurrencyExchangeRateClientFallsBackToLastKnownRateWhenLiveFetchFails() async throws {
        let userDefaults = try isolatedUserDefaults()
        let today = try XCTUnwrap(Self.utcDate(year: 2026, month: 5, day: 19))
        let oldRate = CurrencyExchangeRate(
            baseCurrency: .usd,
            quoteCurrency: .aud,
            rate: 1.42,
            date: "2026-05-18",
            providerName: "Frankfurter"
        )
        CachedCurrencyExchangeRateClient.save(oldRate, userDefaults: userDefaults)
        let client = CachedCurrencyExchangeRateClient(
            liveClient: ThrowingExchangeRateClient(),
            userDefaults: userDefaults,
            now: { today }
        )

        let fetchedRate = try await client.latestRate(from: .usd, to: .aud)
        XCTAssertEqual(fetchedRate, oldRate)
    }

    func testCachedCurrencyExchangeRateClientThrowsWhenNoLiveOrCachedRateExists() async throws {
        let userDefaults = try isolatedUserDefaults()
        let client = CachedCurrencyExchangeRateClient(
            liveClient: ThrowingExchangeRateClient(),
            userDefaults: userDefaults
        )

        do {
            _ = try await client.latestRate(from: .usd, to: .aud)
            XCTFail("Expected missing live and cached AUD conversion to throw")
        } catch CurrencyExchangeRateError.missingRate(let base, let quote) {
            XCTAssertEqual(base, "USD")
            XCTAssertEqual(quote, "AUD")
        }
    }

    private func isolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "CurrencyExchangeRateTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private static func utcDate(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

private struct FixedExchangeRateClient: CurrencyExchangeRateClient {
    var rate: CurrencyExchangeRate

    func latestRate(
        from baseCurrency: CardValueDisplayCurrency,
        to quoteCurrency: CardValueDisplayCurrency
    ) async throws -> CurrencyExchangeRate {
        rate
    }
}

private struct ThrowingExchangeRateClient: CurrencyExchangeRateClient {
    func latestRate(
        from baseCurrency: CardValueDisplayCurrency,
        to quoteCurrency: CardValueDisplayCurrency
    ) async throws -> CurrencyExchangeRate {
        throw CurrencyExchangeRateError.missingRate(baseCurrency.rawValue, quoteCurrency.rawValue)
    }
}
