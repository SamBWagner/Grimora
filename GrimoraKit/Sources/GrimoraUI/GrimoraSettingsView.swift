import GrimoraCore
import SwiftUI

public struct GrimoraSettingsView: View {
  @Environment(GrimoraAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @AppStorage(GrimoraSearchPreferences.defaultSearchTextKey)
  private var defaultSearchText = GrimoraSearchPreferences.defaultSearchText

  @AppStorage(GrimoraSearchPreferences.alwaysIncludedSearchTextKey)
  private var alwaysIncludedSearchText = GrimoraSearchPreferences.defaultAlwaysIncludedSearchText

  @AppStorage(GrimoraSearchPreferences.defaultSearchSortModeKey)
  private var defaultSearchSortModeRawValue = GrimoraSearchPreferences.defaultSortMode.rawValue

  @AppStorage(GrimoraSearchPreferences.defaultSearchSortDirectionKey)
  private var defaultSearchSortDirectionRawValue =
    GrimoraSearchPreferences.defaultSortDirection.rawValue

  @AppStorage(GrimoraSearchPreferences.advancedSearchEnabledKey)
  private var advancedSearchEnabled = GrimoraSearchPreferences.defaultAdvancedSearchEnabled

  // Default-search edits are held locally while the dialog is open so typing
  // never triggers a live search; they are flushed to @AppStorage (which
  // GrimoraRootView observes) only when the dialog closes/confirms (S4).
  @State private var draftDefaultSearchText = GrimoraSearchPreferences.defaultSearchText
  @State private var draftAlwaysIncludedSearchText =
    GrimoraSearchPreferences.defaultAlwaysIncludedSearchText
  @State private var draftSearchSortModeRawValue = GrimoraSearchPreferences.defaultSortMode.rawValue
  @State private var draftSearchSortDirectionRawValue =
    GrimoraSearchPreferences.defaultSortDirection.rawValue
  @State private var hasLoadedDefaultSearchDraft = false

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

      legalForm
      .tabItem {
        Label("Legal", systemImage: "info.circle")
      }
    }
    .frame(width: 500, height: 360)
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
          text: $draftDefaultSearchText,
          prompt: Text("is:commander mv<5")
        )
        .searchSyntaxTextInput()
        .accessibilityIdentifier("default-search-text-field")

        TextField(
          "Always Included",
          text: $draftAlwaysIncludedSearchText,
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

        Toggle("Show advanced search builder", isOn: $advancedSearchEnabled)
          .accessibilityIdentifier("advanced-search-enabled-toggle")
        Text("Adds an on-screen button to build Scryfall queries with toggles and pickers.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Always Hidden") {
        if model.hiddenSearchTerms.isEmpty {
          Text("No card traits are excluded from every search.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("These exclusions affect every search and sync through iCloud.")
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(model.hiddenSearchTerms) { refinement in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(refinement.displayLabel)
                Text(refinement.queryFragment)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button(
                "Remove \(refinement.displayLabel)",
                systemImage: "minus.circle",
                role: .destructive
              ) {
                model.removeHiddenTerm(refinement)
              }
              .labelStyle(.iconOnly)
              .accessibilityIdentifier("remove-hidden-search-term-\(refinement.id)")
            }
          }

          Button("Clear All Always Hidden", role: .destructive) {
            model.clearHiddenTerms()
          }
          .accessibilityIdentifier("clear-hidden-search-terms")
        }
      }

      GrimoraSettingsTutorialSection(onReplay: replayTutorial)

      #if os(iOS) || os(visionOS)
      GrimoraSettingsValueSection()

      GrimoraSettingsSyncSections()

      GrimoraSettingsLegalSections()
      #endif
    }
    .onAppear { loadDefaultSearchDraftIfNeeded() }
    .onDisappear { commitDefaultSearchDraft() }
  }

  private func replayTutorial() {
    model.requestOnboardingReplay()
    dismiss()
  }

  private var valueForm: some View {
    Form {
      GrimoraSettingsValueSection()
    }
  }

  private var legalForm: some View {
    Form {
      GrimoraSettingsLegalSections()
    }
  }

  private var syncForm: some View {
    Form {
      GrimoraSettingsSyncSections()
    }
  }

  private var selectedSortMode: SortMode {
    GrimoraSearchPreferences.sortMode(from: draftSearchSortModeRawValue)
  }

  private var sortMode: Binding<SortMode> {
    Binding {
      selectedSortMode
    } set: { newValue in
      draftSearchSortModeRawValue = newValue.rawValue
    }
  }

  private var selectedSortDirection: SearchSortDirection {
    GrimoraSearchPreferences.sortDirection(from: draftSearchSortDirectionRawValue)
  }

  private var sortDirection: Binding<SearchSortDirection> {
    Binding {
      selectedSortDirection
    } set: { newValue in
      draftSearchSortDirectionRawValue = newValue.rawValue
    }
  }

  private var validationMessage: String? {
    let configuration = GrimoraDefaultSearchConfiguration(
      text: draftDefaultSearchText,
      alwaysIncludedText: draftAlwaysIncludedSearchText,
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

  private func loadDefaultSearchDraftIfNeeded() {
    guard !hasLoadedDefaultSearchDraft else {
      return
    }
    draftDefaultSearchText = defaultSearchText
    draftAlwaysIncludedSearchText = alwaysIncludedSearchText
    draftSearchSortModeRawValue = defaultSearchSortModeRawValue
    draftSearchSortDirectionRawValue = defaultSearchSortDirectionRawValue
    hasLoadedDefaultSearchDraft = true
  }

  private func commitDefaultSearchDraft() {
    guard hasLoadedDefaultSearchDraft else {
      return
    }
    // Only write the keys that actually changed so an unedited open/close
    // does not bump GrimoraRootView's preference observer at all.
    if defaultSearchText != draftDefaultSearchText {
      defaultSearchText = draftDefaultSearchText
    }
    if alwaysIncludedSearchText != draftAlwaysIncludedSearchText {
      alwaysIncludedSearchText = draftAlwaysIncludedSearchText
    }
    if defaultSearchSortModeRawValue != draftSearchSortModeRawValue {
      defaultSearchSortModeRawValue = draftSearchSortModeRawValue
    }
    if defaultSearchSortDirectionRawValue != draftSearchSortDirectionRawValue {
      defaultSearchSortDirectionRawValue = draftSearchSortDirectionRawValue
    }
    hasLoadedDefaultSearchDraft = false
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
