import Foundation
#if canImport(UIKit)
  import UIKit
#endif

enum GrimoraDeviceKind: Equatable, Sendable {
  case mac
  case iPhone
  case iPad
  case visionPro

  var fallbackName: String {
    switch self {
    case .mac:
      "This Mac"
    case .iPhone:
      "This iPhone"
    case .iPad:
      "This iPad"
    case .visionPro:
      "This Apple Vision Pro"
    }
  }

  var genericNames: Set<String> {
    switch self {
    case .mac:
      ["mac", "macbook", "macbook pro", "imac", "grimora device"]
    case .iPhone:
      ["iphone", "grimora device"]
    case .iPad:
      ["ipad", "grimora device"]
    case .visionPro:
      ["apple vision pro", "vision pro", "grimora device"]
    }
  }
}

enum GrimoraDeviceLabel {
  @MainActor
  static var current: String {
    #if os(macOS)
      displayName(
        reportedName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        kind: .mac
      )
    #elseif os(visionOS)
      displayName(reportedName: UIDevice.current.name, kind: .visionPro)
    #elseif os(iOS)
      let kind: GrimoraDeviceKind = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
      return displayName(reportedName: UIDevice.current.name, kind: kind)
    #else
      return "This Device"
    #endif
  }

  static func displayName(
    reportedName: String?,
    kind: GrimoraDeviceKind
  ) -> String {
    let trimmed = reportedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty,
      !kind.genericNames.contains(trimmed.lowercased())
    else {
      return kind.fallbackName
    }
    return trimmed
  }
}
