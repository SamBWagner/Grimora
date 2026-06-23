import Foundation
import GrimoraCore

public struct GrimoraDefaultSearchConfiguration: Equatable, Sendable {
  public var text: String
  public var alwaysIncludedText: String
  public var sortMode: SortMode
  public var sortDirection: SearchSortDirection

  public init(
    text: String = GrimoraSearchPreferences.defaultSearchText,
    alwaysIncludedText: String = GrimoraSearchPreferences.defaultAlwaysIncludedSearchText,
    sortMode: SortMode = GrimoraSearchPreferences.defaultSortMode,
    sortDirection: SearchSortDirection = GrimoraSearchPreferences.defaultSortDirection
  ) {
    self.text = text
    self.alwaysIncludedText = alwaysIncludedText
    self.sortMode = sortMode
    self.sortDirection = sortDirection
  }

  public var normalizedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var normalizedAlwaysIncludedText: String {
    alwaysIncludedText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var isEnabled: Bool {
    !normalizedText.isEmpty
  }

  public func searchText(includingAlwaysIncluded query: String) -> String {
    let included = normalizedAlwaysIncludedText
    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !included.isEmpty else {
      return search
    }
    guard !search.isEmpty else {
      return included
    }
    return "\(included) \(search)"
  }
}

public enum GrimoraSearchPreferences {
  public static let defaultSearchTextKey = "Grimora.defaultSearch.text"
  public static let alwaysIncludedSearchTextKey = "Grimora.search.alwaysIncludedText"
  public static let defaultSearchSortModeKey = "Grimora.defaultSearch.sortMode"
  public static let defaultSearchSortDirectionKey = "Grimora.defaultSearch.sortDirection"
  public static let searchInputModeKey = "Grimora.search.inputMode"
  public static let searchHistoryKey = "Grimora.searchHistory.queries"
  public static let plainTextSearchHistoryKey = "Grimora.plainTextSearchHistory.queries"
  public static let hiddenSearchTermsKey = "Grimora.search.hiddenTerms"
  public static let advancedSearchEnabledKey = "Grimora.search.advancedFormEnabled"

  public static let defaultSearchText = ""
  public static let defaultAlwaysIncludedSearchText = ""
  public static let defaultSortMode = SortMode.releaseDate
  public static let defaultSortDirection = SearchSortDirection.ascending
  public static let defaultSearchInputMode = SearchInputMode.scryfall
  public static let isPlainTextSearchInterfaceEnabled = false
  /// Whether the on-screen advanced-search builder affordance is offered. On by
  /// default; users who only use raw Scryfall syntax can hide it in Settings.
  public static let defaultAdvancedSearchEnabled = true

  public static func configuration(
    text: String,
    alwaysIncludedText: String = defaultAlwaysIncludedSearchText,
    sortModeRawValue: String,
    sortDirectionRawValue: String
  ) -> GrimoraDefaultSearchConfiguration {
    GrimoraDefaultSearchConfiguration(
      text: text,
      alwaysIncludedText: alwaysIncludedText,
      sortMode: sortMode(from: sortModeRawValue),
      sortDirection: sortDirection(from: sortDirectionRawValue)
    )
  }

  public static func configuration(userDefaults: UserDefaults = .standard)
    -> GrimoraDefaultSearchConfiguration
  {
    configuration(
      text: userDefaults.string(forKey: defaultSearchTextKey) ?? defaultSearchText,
      alwaysIncludedText: userDefaults.string(forKey: alwaysIncludedSearchTextKey)
        ?? defaultAlwaysIncludedSearchText,
      sortModeRawValue: userDefaults.string(forKey: defaultSearchSortModeKey)
        ?? defaultSortMode.rawValue,
      sortDirectionRawValue: userDefaults.string(forKey: defaultSearchSortDirectionKey)
        ?? defaultSortDirection.rawValue
    )
  }

  public static func sortMode(from rawValue: String) -> SortMode {
    SortMode(rawValue: rawValue) ?? defaultSortMode
  }

  public static func sortDirection(from rawValue: String) -> SearchSortDirection {
    SearchSortDirection(rawValue: rawValue) ?? defaultSortDirection
  }

  public static func searchInputMode(from rawValue: String) -> SearchInputMode {
    SearchInputMode(rawValue: rawValue) ?? defaultSearchInputMode
  }

  public static func searchInputMode(userDefaults: UserDefaults = .standard) -> SearchInputMode {
    searchInputMode(
      from: userDefaults.string(forKey: searchInputModeKey) ?? defaultSearchInputMode.rawValue
    )
  }

  public static func directionTitle(
    _ direction: SearchSortDirection,
    for sortMode: SortMode
  ) -> String {
    switch (sortMode, direction) {
    case (.releaseDate, .ascending):
      "Newest First"
    case (.releaseDate, .descending):
      "Oldest First"
    case (_, .ascending):
      "Ascending"
    case (_, .descending):
      "Descending"
    }
  }

  public static func sortDescription(
    sortMode: SortMode,
    sortDirection: SearchSortDirection
  ) -> String {
    "\(sortMode.title), \(directionTitle(sortDirection, for: sortMode))"
  }
}
