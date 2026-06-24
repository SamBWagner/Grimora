import SwiftUI

// FocusedValues keys backing the macOS/iPad menu + command layer.
//
// These replace the `ObservableObject`-only focus API (`@FocusedObject` /
// `.focusedSceneObject`) after the migration to `@Observable`, which requires
// `@FocusedValue` / `.focusedSceneValue(\.key, value)` instead.

extension FocusedValues {
    var gridZoomController: GridZoomController? {
        get { self[GridZoomControllerFocusedValueKey.self] }
        set { self[GridZoomControllerFocusedValueKey.self] = newValue }
    }

    var libraryMaintenanceController: GrimoraLibraryMaintenanceController? {
        get { self[GrimoraLibraryMaintenanceControllerFocusedValueKey.self] }
        set { self[GrimoraLibraryMaintenanceControllerFocusedValueKey.self] = newValue }
    }
}

private struct GridZoomControllerFocusedValueKey: FocusedValueKey {
    typealias Value = GridZoomController
}

private struct GrimoraLibraryMaintenanceControllerFocusedValueKey: FocusedValueKey {
    typealias Value = GrimoraLibraryMaintenanceController
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
