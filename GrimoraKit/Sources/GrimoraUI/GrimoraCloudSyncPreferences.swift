import Foundation

public enum GrimoraCloudSyncPreferences {
  public static let modeKey = "Grimora.cloudSync.mode"
  public static let deviceIDKey = "Grimora.cloudSync.deviceID"

  public static func deviceID(userDefaults: UserDefaults = .standard) -> String {
    if let existing = userDefaults.string(forKey: deviceIDKey), !existing.isEmpty {
      return existing
    }

    let created = UUID().uuidString.lowercased()
    userDefaults.set(created, forKey: deviceIDKey)
    return created
  }
}

