import Foundation

public enum CardValueDisplayCurrency: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
  case usd = "USD"
  case aud = "AUD"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .usd:
      "USD"
    case .aud:
      "AUD"
    }
  }
}

public enum GrimoraValuePreferences {
  public static let displayCurrencyKey = "Grimora.value.displayCurrency"

  public static func displayCurrency(from rawValue: String) -> CardValueDisplayCurrency {
    CardValueDisplayCurrency(rawValue: rawValue) ?? .usd
  }
}

public struct CurrencyExchangeRate: Codable, Equatable, Sendable {
  public var baseCurrency: CardValueDisplayCurrency
  public var quoteCurrency: CardValueDisplayCurrency
  public var rate: Double
  public var date: String
  public var providerName: String

  public init(
    baseCurrency: CardValueDisplayCurrency,
    quoteCurrency: CardValueDisplayCurrency,
    rate: Double,
    date: String,
    providerName: String
  ) {
    self.baseCurrency = baseCurrency
    self.quoteCurrency = quoteCurrency
    self.rate = rate
    self.date = date
    self.providerName = providerName
  }
}

public protocol CurrencyExchangeRateClient: Sendable {
  func latestRate(
    from baseCurrency: CardValueDisplayCurrency,
    to quoteCurrency: CardValueDisplayCurrency
  ) async throws -> CurrencyExchangeRate
}

public struct FrankfurterCurrencyExchangeRateClient: CurrencyExchangeRateClient {
  public static let providerName = "Frankfurter"

  private let network: NetworkClient
  private let decoder: JSONDecoder

  public init(network: NetworkClient, decoder: JSONDecoder = JSONDecoder()) {
    self.network = network
    self.decoder = decoder
  }

  public func latestRate(
    from baseCurrency: CardValueDisplayCurrency,
    to quoteCurrency: CardValueDisplayCurrency
  ) async throws -> CurrencyExchangeRate {
    guard baseCurrency != quoteCurrency else {
      return CurrencyExchangeRate(
        baseCurrency: baseCurrency,
        quoteCurrency: quoteCurrency,
        rate: 1,
        date: Self.todayString(),
        providerName: Self.providerName
      )
    }

    let data = try await network.data(
      from: Self.latestRateURL(from: baseCurrency, to: quoteCurrency),
      purpose: .priceHistoryDownload
    )
    let rows = try decoder.decode([FrankfurterRateRow].self, from: data)
    guard let row = rows.first else {
      throw CurrencyExchangeRateError.missingRate(baseCurrency.rawValue, quoteCurrency.rawValue)
    }
    return CurrencyExchangeRate(
      baseCurrency: baseCurrency,
      quoteCurrency: quoteCurrency,
      rate: row.rate,
      date: row.date,
      providerName: Self.providerName
    )
  }

  public static func latestRateURL(
    from baseCurrency: CardValueDisplayCurrency,
    to quoteCurrency: CardValueDisplayCurrency
  ) -> URL {
    var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
    components.queryItems = [
      URLQueryItem(name: "base", value: baseCurrency.rawValue),
      URLQueryItem(name: "quotes", value: quoteCurrency.rawValue),
    ]
    return components.url!
  }

  private static func todayString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }
}

public final class CachedCurrencyExchangeRateClient: CurrencyExchangeRateClient, @unchecked Sendable {
  private let liveClient: any CurrencyExchangeRateClient
  private let userDefaults: UserDefaults
  private let calendar: Calendar
  private let now: @Sendable () -> Date

  public init(
    liveClient: any CurrencyExchangeRateClient,
    userDefaults: UserDefaults = .standard,
    calendar: Calendar = Calendar(identifier: .gregorian),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.liveClient = liveClient
    self.userDefaults = userDefaults
    var utcCalendar = calendar
    utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    self.calendar = utcCalendar
    self.now = now
  }

  public func latestRate(
    from baseCurrency: CardValueDisplayCurrency,
    to quoteCurrency: CardValueDisplayCurrency
  ) async throws -> CurrencyExchangeRate {
    guard baseCurrency != quoteCurrency else {
      return CurrencyExchangeRate(
        baseCurrency: baseCurrency,
        quoteCurrency: quoteCurrency,
        rate: 1,
        date: Self.cacheDayString(for: now(), calendar: calendar),
        providerName: "Identity"
      )
    }

    if let cached = Self.cachedRate(
      from: baseCurrency,
      to: quoteCurrency,
      userDefaults: userDefaults
    ),
      cached.date == Self.cacheDayString(for: now(), calendar: calendar)
    {
      return cached
    }

    do {
      let liveRate = try await liveClient.latestRate(from: baseCurrency, to: quoteCurrency)
      Self.save(liveRate, userDefaults: userDefaults)
      return liveRate
    } catch {
      if let cached = Self.cachedRate(
        from: baseCurrency,
        to: quoteCurrency,
        userDefaults: userDefaults
      ) {
        return cached
      }
      throw error
    }
  }

  public static func cachedRate(
    from baseCurrency: CardValueDisplayCurrency,
    to quoteCurrency: CardValueDisplayCurrency,
    userDefaults: UserDefaults = .standard
  ) -> CurrencyExchangeRate? {
    let prefix = cacheKeyPrefix(from: baseCurrency, to: quoteCurrency)
    let rate = userDefaults.double(forKey: "\(prefix).rate")
    guard rate > 0,
      let date = userDefaults.string(forKey: "\(prefix).date"),
      let providerName = userDefaults.string(forKey: "\(prefix).provider")
    else {
      return nil
    }

    return CurrencyExchangeRate(
      baseCurrency: baseCurrency,
      quoteCurrency: quoteCurrency,
      rate: rate,
      date: date,
      providerName: providerName
    )
  }

  public static func save(_ rate: CurrencyExchangeRate, userDefaults: UserDefaults = .standard) {
    let prefix = cacheKeyPrefix(from: rate.baseCurrency, to: rate.quoteCurrency)
    userDefaults.set(rate.rate, forKey: "\(prefix).rate")
    userDefaults.set(rate.date, forKey: "\(prefix).date")
    userDefaults.set(rate.providerName, forKey: "\(prefix).provider")
  }

  private static func cacheKeyPrefix(
    from baseCurrency: CardValueDisplayCurrency,
    to quoteCurrency: CardValueDisplayCurrency
  ) -> String {
    "Grimora.value.exchangeRate.\(baseCurrency.rawValue).\(quoteCurrency.rawValue)"
  }

  private static func cacheDayString(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }
}

public enum CurrencyExchangeRateError: Error, Equatable, Sendable {
  case missingRate(String, String)
}

private struct FrankfurterRateRow: Decodable {
  var date: String
  var rate: Double
}
