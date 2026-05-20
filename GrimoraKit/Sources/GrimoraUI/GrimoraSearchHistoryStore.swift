import Foundation

public final class GrimoraSearchHistoryStore: @unchecked Sendable {
  public static let maxQueryCount = 10

  private let userDefaults: UserDefaults
  private let key: String

  public init(
    userDefaults: UserDefaults = .standard,
    key: String = GrimoraSearchPreferences.searchHistoryKey
  ) {
    self.userDefaults = userDefaults
    self.key = key
  }

  public func load() -> [String] {
    Self.normalizedHistory(userDefaults.stringArray(forKey: key) ?? [])
  }

  public func save(_ history: [String]) {
    let normalizedHistory = Self.normalizedHistory(history)
    if normalizedHistory.isEmpty {
      userDefaults.removeObject(forKey: key)
    } else {
      userDefaults.set(normalizedHistory, forKey: key)
    }
  }

  public func clear() {
    userDefaults.removeObject(forKey: key)
  }

  public func historyByRecording(_ query: String, in history: [String]) -> [String] {
    Self.historyByRecording(query, in: history)
  }

  static func historyByRecording(_ query: String, in history: [String]) -> [String] {
    let normalizedQuery = normalizedQuery(query)
    guard !normalizedQuery.isEmpty else {
      return normalizedHistory(history)
    }

    var updatedHistory = normalizedHistory(history).filter { $0 != normalizedQuery }
    updatedHistory.insert(normalizedQuery, at: 0)
    return Array(updatedHistory.prefix(maxQueryCount))
  }

  static func normalizedHistory(_ history: [String]) -> [String] {
    var normalizedHistory: [String] = []
    for query in history {
      let normalizedQuery = normalizedQuery(query)
      guard !normalizedQuery.isEmpty, !normalizedHistory.contains(normalizedQuery) else {
        continue
      }

      normalizedHistory.append(normalizedQuery)
      if normalizedHistory.count == maxQueryCount {
        break
      }
    }
    return normalizedHistory
  }

  static func normalizedQuery(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
