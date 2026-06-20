import Foundation

public enum GrimoraCloudSyncPreferences {
  public static let modeKey = "Grimora.cloudSync.mode"
  public static let deviceIDKey = "Grimora.cloudSync.deviceID"
  public static let searchSettingsUpdatedAtKey = "Grimora.cloudSync.searchSettingsUpdatedAt"
  public static let accountConsentKey = "Grimora.cloudSync.accountConsent"

  public static func resolvedMode(
    userDefaults: UserDefaults = .standard,
    ubiquitousStore: NSUbiquitousKeyValueStore = .default
  ) -> GrimoraCloudSyncMode {
    if ProcessInfo.processInfo.environment["GRIMORA_TEST_ENABLE_CLOUD_SYNC"] == "1" {
      return .enabled
    }
    if let stored = userDefaults.string(forKey: modeKey)
      .flatMap(GrimoraCloudSyncMode.init(rawValue:))
    {
      return stored
    }
    ubiquitousStore.synchronize()
    return ubiquitousStore.bool(forKey: accountConsentKey) ? .enabled : .undecided
  }

  public static func persistAccountConsent(
    ubiquitousStore: NSUbiquitousKeyValueStore = .default
  ) {
    ubiquitousStore.set(true, forKey: accountConsentKey)
    ubiquitousStore.synchronize()
  }

  public static func deviceID(userDefaults: UserDefaults = .standard) -> String {
    if let existing = userDefaults.string(forKey: deviceIDKey), !existing.isEmpty {
      return existing
    }

    let created = UUID().uuidString.lowercased()
    userDefaults.set(created, forKey: deviceIDKey)
    return created
  }

  public static func searchSettingsUpdatedAt(userDefaults: UserDefaults = .standard) -> Date {
    if let existing = userDefaults.object(forKey: searchSettingsUpdatedAtKey) as? Date {
      return existing
    }

    return .distantPast
  }
}
