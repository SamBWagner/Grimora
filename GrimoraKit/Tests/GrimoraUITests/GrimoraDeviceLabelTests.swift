@testable import GrimoraUI
import XCTest

final class GrimoraDeviceLabelTests: XCTestCase {
  func testGenericDeviceNamesUsePlatformSpecificFallbacks() {
    XCTAssertEqual(
      GrimoraDeviceLabel.displayName(reportedName: "iPhone", kind: .iPhone),
      "This iPhone"
    )
    XCTAssertEqual(
      GrimoraDeviceLabel.displayName(reportedName: "iPad", kind: .iPad),
      "This iPad"
    )
    XCTAssertEqual(
      GrimoraDeviceLabel.displayName(reportedName: "Apple Vision Pro", kind: .visionPro),
      "This Apple Vision Pro"
    )
    XCTAssertEqual(
      GrimoraDeviceLabel.displayName(reportedName: "Grimora Device", kind: .mac),
      "This Mac"
    )
  }

  func testUserAssignedDeviceNameIsPreservedWhenAvailable() {
    XCTAssertEqual(
      GrimoraDeviceLabel.displayName(reportedName: "Sam's iPhone", kind: .iPhone),
      "Sam's iPhone"
    )
  }

  func testBlankDeviceNameUsesFallback() {
    XCTAssertEqual(
      GrimoraDeviceLabel.displayName(reportedName: "  ", kind: .iPad),
      "This iPad"
    )
  }
}
