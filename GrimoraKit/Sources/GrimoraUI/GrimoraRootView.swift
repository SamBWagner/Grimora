import GrimoraCore
import SwiftUI


public struct GrimoraRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GrimoraAppModel
    @State private var onboarding = GrimoraOnboardingModel()
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
    private var displayCurrencyRawValue = CardValueDisplayCurrency.usd.rawValue

    public init(environment: GrimoraEnvironment) {
        _model = State(
            wrappedValue: GrimoraAppModel.configuredForCurrentPreferences(environment: environment)
        )
    }

    public init(model: GrimoraAppModel) {
        _model = State(wrappedValue: model)
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

            if onboarding.isActive, model.libraryActivity == nil {
                OnboardingTutorialView(onboarding: onboarding)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(model)
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
        .overlay(alignment: .bottom) {
            if let notice = model.cloudSyncMergeNotice {
                CloudSyncMergeNoticeBanner(
                    notice: notice,
                    onUndo: { model.undoCloudSyncMerge() },
                    onDismiss: { model.dismissCloudSyncMergeNotice() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.cloudSyncMergeNotice)
        .onAppear {
            if cloudSyncModePreference == .undecided, model.cloudSyncMode == .enabled {
                cloudSyncModeRawValue = GrimoraCloudSyncMode.enabled.rawValue
            }
            model.applySearchPreferences(searchPreferenceConfiguration)
            model.applyCloudSyncModePreference(cloudSyncModePreference)
        }
        .onChange(of: searchPreferenceConfiguration) { _, newValue in
            model.applySearchPreferences(newValue)
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
        .onChange(of: model.hasLibrary) { _, isReady in
            if isReady {
                onboarding.libraryDidBecomeReady()
            }
        }
        .onChange(of: model.onboardingReplayRequestID) { _, _ in
            onboarding.restart()
        }
        .animation(.easeInOut(duration: 0.18), value: model.libraryActivity)
        .animation(.easeInOut(duration: 0.18), value: onboarding.isActive)
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

    private var cloudSyncModePreference: GrimoraCloudSyncMode {
        GrimoraCloudSyncMode(rawValue: cloudSyncModeRawValue) ?? .undecided
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
