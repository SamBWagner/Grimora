import GrimoraCore
import SwiftUI

public struct GrimoraSettingsView: View {
  @AppStorage(GrimoraSearchPreferences.defaultSearchTextKey)
  private var defaultSearchText = GrimoraSearchPreferences.defaultSearchText

  @AppStorage(GrimoraSearchPreferences.alwaysIncludedSearchTextKey)
  private var alwaysIncludedSearchText = GrimoraSearchPreferences.defaultAlwaysIncludedSearchText

  @AppStorage(GrimoraSearchPreferences.defaultSearchSortModeKey)
  private var defaultSearchSortModeRawValue = GrimoraSearchPreferences.defaultSortMode.rawValue

  @AppStorage(GrimoraSearchPreferences.defaultSearchSortDirectionKey)
  private var defaultSearchSortDirectionRawValue =
    GrimoraSearchPreferences.defaultSortDirection.rawValue

  @AppStorage(GrimoraCloudSyncPreferences.modeKey)
  private var cloudSyncModeRawValue = GrimoraCloudSyncMode.undecided.rawValue

  @AppStorage(GrimoraValuePreferences.displayCurrencyKey)
  private var valueDisplayCurrencyRawValue = CardValueDisplayCurrency.usd.rawValue

  public init() {}

  public var body: some View {
    #if os(macOS)
    TabView {
      settingsForm
      .tabItem {
        Label("Search", systemImage: "magnifyingglass")
      }

      syncForm
      .tabItem {
        Label("Sync", systemImage: "icloud")
      }

      valueForm
      .tabItem {
        Label("Value", systemImage: "chart.line.uptrend.xyaxis")
      }
    }
    .frame(width: 500, height: 340)
    .scenePadding()
    #elseif os(iOS) || os(visionOS)
    settingsForm
    #endif
  }

  private var settingsForm: some View {
    Form {
      Section("Default Search") {
        TextField(
          "Query",
          text: $defaultSearchText,
          prompt: Text("is:commander mv<5")
        )
        .searchSyntaxTextInput()
        .accessibilityIdentifier("default-search-text-field")

        TextField(
          "Always Included",
          text: $alwaysIncludedSearchText,
          prompt: Text("legal:commander")
        )
        .searchSyntaxTextInput()
        .accessibilityIdentifier("always-included-search-text-field")

        Picker("Sort", selection: sortMode) {
          ForEach(SortMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .accessibilityIdentifier("default-search-sort-picker")

        Picker("Direction", selection: sortDirection) {
          ForEach(searchSortDirections, id: \.self) { direction in
            Text(GrimoraSearchPreferences.directionTitle(direction, for: selectedSortMode))
              .tag(direction)
          }
        }
        .accessibilityIdentifier("default-search-direction-picker")

        if let validationMessage {
          Label(validationMessage, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("default-search-validation")
        }
      }

      #if os(iOS) || os(visionOS)
      valueSection

      Section("iCloud") {
        Toggle("Sync lists and search settings", isOn: cloudSyncEnabled)
          .accessibilityIdentifier("cloud-sync-toggle")

        Text("Card data stays local. Grimora only uses iCloud to keep devices on the same Scryfall database version before syncing lists.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      #endif
    }
  }

  private var valueForm: some View {
    Form {
      valueSection
    }
  }

  private var valueSection: some View {
    Section("Value Display") {
      Picker("Currency", selection: valueDisplayCurrency) {
        ForEach(CardValueDisplayCurrency.allCases) { currency in
          Text(currency.title).tag(currency)
        }
      }
      .accessibilityIdentifier("value-currency-picker")

      Text("AUD values are converted from USD with a cached daily exchange rate.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var syncForm: some View {
    Form {
      Section("iCloud") {
        Toggle("Sync lists and search settings", isOn: cloudSyncEnabled)
          .accessibilityIdentifier("cloud-sync-toggle")

        Text("Card data stays local. Grimora only uses iCloud to keep devices on the same Scryfall database version before syncing lists.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var selectedSortMode: SortMode {
    GrimoraSearchPreferences.sortMode(from: defaultSearchSortModeRawValue)
  }

  private var sortMode: Binding<SortMode> {
    Binding {
      selectedSortMode
    } set: { newValue in
      defaultSearchSortModeRawValue = newValue.rawValue
    }
  }

  private var selectedSortDirection: SearchSortDirection {
    GrimoraSearchPreferences.sortDirection(from: defaultSearchSortDirectionRawValue)
  }

  private var sortDirection: Binding<SearchSortDirection> {
    Binding {
      selectedSortDirection
    } set: { newValue in
      defaultSearchSortDirectionRawValue = newValue.rawValue
    }
  }

  private var valueDisplayCurrency: Binding<CardValueDisplayCurrency> {
    Binding {
      GrimoraValuePreferences.displayCurrency(from: valueDisplayCurrencyRawValue)
    } set: { newValue in
      valueDisplayCurrencyRawValue = newValue.rawValue
    }
  }

  private var validationMessage: String? {
    let configuration = GrimoraDefaultSearchConfiguration(
      text: defaultSearchText,
      alwaysIncludedText: alwaysIncludedSearchText,
      sortMode: selectedSortMode,
      sortDirection: selectedSortDirection
    )
    let text = configuration.searchText(includingAlwaysIncluded: configuration.normalizedText)
    guard !text.isEmpty else {
      return nil
    }

    return SearchQuery.unsupportedReason(for: text)?.message
  }

  private var searchSortDirections: [SearchSortDirection] {
    [.ascending, .descending]
  }

  private var cloudSyncEnabled: Binding<Bool> {
    Binding {
      GrimoraCloudSyncMode(rawValue: cloudSyncModeRawValue) == .enabled
    } set: { isEnabled in
      cloudSyncModeRawValue = isEnabled
        ? GrimoraCloudSyncMode.enabled.rawValue
        : GrimoraCloudSyncMode.disabled.rawValue
    }
  }
}

private extension View {
  @ViewBuilder
  func searchSyntaxTextInput() -> some View {
    #if os(iOS) || os(visionOS)
    self
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
    #else
    self
    #endif
  }
}
