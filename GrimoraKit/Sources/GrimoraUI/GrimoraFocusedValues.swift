import SwiftUI

// FocusedValues keys backing the macOS/iPad menu + command layer.
//
// The controllers expose their focus state through `@FocusedValue` /
// `.focusedSceneValue(\.key, value)`. The earlier focused-object scene API only
// accepted reference types conforming to the legacy observation protocol, so it
// could not carry these @Observable controllers.

extension FocusedValues {
    var gridZoomController: GridZoomController? {
        get { self[GridZoomControllerFocusedValueKey.self] }
        set { self[GridZoomControllerFocusedValueKey.self] = newValue }
    }

    var libraryMaintenanceController: GrimoraLibraryMaintenanceController? {
        get { self[GrimoraLibraryMaintenanceControllerFocusedValueKey.self] }
        set { self[GrimoraLibraryMaintenanceControllerFocusedValueKey.self] = newValue }
    }

    var appModel: GrimoraAppModel? {
        get { self[GrimoraAppModelFocusedValueKey.self] }
        set { self[GrimoraAppModelFocusedValueKey.self] = newValue }
    }
}

private struct GridZoomControllerFocusedValueKey: FocusedValueKey {
    typealias Value = GridZoomController
}

private struct GrimoraLibraryMaintenanceControllerFocusedValueKey: FocusedValueKey {
    typealias Value = GrimoraLibraryMaintenanceController
}

private struct GrimoraAppModelFocusedValueKey: FocusedValueKey {
    typealias Value = GrimoraAppModel
}

#if os(macOS)
extension FocusedValues {
    var listCommandController: GrimoraListCommandController? {
        get { self[GrimoraListCommandControllerFocusedValueKey.self] }
        set { self[GrimoraListCommandControllerFocusedValueKey.self] = newValue }
    }
}

private struct GrimoraListCommandControllerFocusedValueKey: FocusedValueKey {
    typealias Value = GrimoraListCommandController
}
#endif
