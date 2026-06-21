import GrimoraCore
import SwiftUI


public struct GrimoraRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: GrimoraAppModel
    @AppStorage(GrimoraSearchPreferences.defaultSearchTextKey)
    private var defaultSearchText = GrimoraSearchPreferences.defaultSearchText
    @AppStorage(GrimoraSearchPreferences.alwaysIncludedSearchTextKey)
    private var alwaysIncludedSearchText = GrimoraSearchPreferences.defaultAlwaysIncludedSearchText
    @AppStorage(GrimoraSearchPreferences.defaultSearchSortModeKey)
    private var defaultSearchSortModeRawValue = GrimoraSearchPreferences.defaultSortMode.rawValue
    @AppStorage(GrimoraSearchPreferences.defaultSearchSortDirectionKey)
    private var defaultSearchSortDirectionRawValue =
        GrimoraSearchPreferences.defaultSortDirection.rawValue
    @AppStorage(GrimoraSearchPreferences.searchInputModeKey)
    private var searchInputModeRawValue = GrimoraSearchPreferences.defaultSearchInputMode.rawValue
    @AppStorage(GrimoraCloudSyncPreferences.modeKey)
    private var cloudSyncModeRawValue = GrimoraCloudSyncMode.undecided.rawValue
    @AppStorage(GrimoraValuePreferences.displayCurrencyKey)
    private var displayCurrencyRawValue = CardValueDisplayCurrency.usd.rawValue

    public init(environment: GrimoraEnvironment) {
        _model = StateObject(
            wrappedValue: GrimoraAppModel.configuredForCurrentPreferences(environment: environment)
        )
    }

    public init(model: GrimoraAppModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            if let activity = model.libraryActivity {
                DataLoadScreen(activity: activity) {
                    model.dismissLibraryActivity()
                }
                .transition(.opacity)
            } else {
                root
                    .transition(.opacity)
            }
        }
        .environmentObject(model)
        .platformChromeTint(palette: palette)
        .background {
            GrimoraAppBackground(palette: palette)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["GRIMORA_SYNC_TEST_EXPOSE_STATUS"] == "1" {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("cloud-sync-test-status")
                    .accessibilityLabel(model.statusMessage)
            }
        }
        .onAppear {
            if cloudSyncModePreference == .undecided, model.cloudSyncMode == .enabled {
                cloudSyncModeRawValue = GrimoraCloudSyncMode.enabled.rawValue
            }
            model.applySearchPreferences(searchPreferenceConfiguration)
            applySearchInputModePreference(searchInputModePreference)
            model.applyCloudSyncModePreference(cloudSyncModePreference)
        }
        .onChange(of: searchPreferenceConfiguration) { _, newValue in
            model.applySearchPreferences(newValue)
        }
        .onChange(of: searchInputModePreference) { _, newValue in
            applySearchInputModePreference(newValue)
        }
        .onChange(of: model.searchInputMode) { _, newValue in
            let effectiveMode = Self.effectiveSearchInputMode(newValue)
            if effectiveMode != newValue {
                model.setSearchInputMode(effectiveMode)
            }
            if searchInputModeRawValue != effectiveMode.rawValue {
                searchInputModeRawValue = effectiveMode.rawValue
            }
        }
        .onChange(of: cloudSyncModePreference) { _, newValue in
            model.applyCloudSyncModePreference(newValue)
        }
        .onChange(of: model.cloudSyncMode) { _, newValue in
            if cloudSyncModeRawValue != newValue.rawValue {
                cloudSyncModeRawValue = newValue.rawValue
            }
        }
        .onChange(of: displayCurrencyRawValue) {
            model.durableCloudSyncPreferencesChanged()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                model.refreshCloudSyncWhenActive()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.libraryActivity)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var searchPreferenceConfiguration: GrimoraDefaultSearchConfiguration {
        GrimoraSearchPreferences.configuration(
            text: defaultSearchText,
            alwaysIncludedText: alwaysIncludedSearchText,
            sortModeRawValue: defaultSearchSortModeRawValue,
            sortDirectionRawValue: defaultSearchSortDirectionRawValue
        )
    }

    private var searchInputModePreference: SearchInputMode {
        GrimoraSearchPreferences.searchInputMode(from: searchInputModeRawValue)
    }

    private var cloudSyncModePreference: GrimoraCloudSyncMode {
        GrimoraCloudSyncMode(rawValue: cloudSyncModeRawValue) ?? .undecided
    }

    private func applySearchInputModePreference(_ mode: SearchInputMode) {
        let effectiveMode = Self.effectiveSearchInputMode(mode)
        if searchInputModeRawValue != effectiveMode.rawValue {
            searchInputModeRawValue = effectiveMode.rawValue
        }
        model.applySearchInputModePreference(effectiveMode)
    }

    private static func effectiveSearchInputMode(_ mode: SearchInputMode) -> SearchInputMode {
        GrimoraSearchPreferences.isPlainTextSearchInterfaceEnabled ? mode : .scryfall
    }

    @ViewBuilder
    private var root: some View {
        if model.cloudSyncResolutionContext != nil {
            CloudSyncResolutionView()
        } else if !model.hasLibrary, model.cloudSyncMode == .undecided, model.canOfferInitialCloudSync {
            CloudSyncSetupView()
        } else if model.hasLibrary {
            #if os(macOS)
            MacRootView()
            #elseif os(iOS) || os(visionOS)
            TouchRootView()
            #endif
        } else {
            LibrarySetupView()
        }
    }
}

private extension View {
    @ViewBuilder
    func platformChromeTint(palette: GrimoraPalette) -> some View {
        #if os(visionOS)
        self
        #else
        self.tint(palette.accent.color)
        #endif
    }
}
