import Foundation
import XCTest

// Shared XCUITest primitives for the touch UI-test suites that ship to both iOS and
// visionOS (this folder backs the `GrimoraiOSUITests` and `GrimoraVisionOSUITests`
// targets). These helpers were previously copy-pasted — byte for byte — into nearly
// every test file here. Hoisting them gives the visionOS target the exact same helper
// surface as iOS, which is what lets the touch tests run unchanged on both platforms.
//
// They are intentionally free functions rather than an `XCTestCase` extension: a few
// files keep a specialised local copy (e.g. onboarding's wait-then-tap `activate`),
// and a subclass method can legally *shadow* a global function but cannot "override" a
// superclass-extension method — the latter is a compile error.

/// The first descendant of `root` whose accessibility identifier matches exactly.
@MainActor
func firstElement(_ root: XCUIElement, identifier: String) -> XCUIElement {
    root.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

/// The first descendant of `root` whose accessibility identifier begins with `prefix`.
@MainActor
func firstElementWithPrefix(_ root: XCUIElement, identifierPrefix: String) -> XCUIElement {
    root.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
        .firstMatch
}

/// The first button whose accessibility label matches `label` exactly.
@MainActor
func button(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
}

/// Activate an element using the platform's primary gesture (tap on touch, click on Mac).
@MainActor
func activate(_ element: XCUIElement) {
    #if os(macOS)
    element.click()
    #else
    element.tap()
    #endif
}

/// Poll until `element` no longer exists, or the timeout elapses.
@MainActor
func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !element.exists { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return !element.exists
}

/// Poll until `element`'s `value` equals `expectedValue`, or the timeout elapses.
@MainActor
func waitForValue(
    of element: XCUIElement,
    toEqual expectedValue: String,
    timeout: TimeInterval = 3
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if element.value as? String == expectedValue { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return element.value as? String == expectedValue
}

/// Poll until `element`'s label or value equals `expectedText`, or the timeout elapses.
@MainActor
func waitForText(
    of element: XCUIElement,
    toEqual expectedText: String,
    timeout: TimeInterval = 3
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if element.label == expectedText || element.value as? String == expectedText { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return element.label == expectedText || element.value as? String == expectedText
}
