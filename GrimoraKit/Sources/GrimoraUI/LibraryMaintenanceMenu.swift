import SwiftUI

@Observable
@MainActor
final class GrimoraLibraryMaintenanceController {
    var pendingConfirmation: LibraryMaintenanceConfirmation?

    func confirm(_ action: LibraryMaintenanceConfirmation) {
        pendingConfirmation = action
    }
}

enum LibraryMaintenanceConfirmation: Identifiable {
    case deleteImages
    case deleteAndRefreshDatabase

    var id: String {
        switch self {
        case .deleteImages:
            "delete-images"
        case .deleteAndRefreshDatabase:
            "delete-and-refresh-database"
        }
    }

    var title: String {
        switch self {
        case .deleteImages:
            "Delete Cached Images?"
        case .deleteAndRefreshDatabase:
            "Delete and Refresh Card Database?"
        }
    }

    var message: String {
        switch self {
        case .deleteImages:
            "This removes cached card images and clears image paths from the card database. Your lists are kept."
        case .deleteAndRefreshDatabase:
            "This downloads a fresh Grimora catalog and removes the cached image files. Your lists are kept."
        }
    }

    var confirmationTitle: String {
        switch self {
        case .deleteImages:
            "Delete Images"
        case .deleteAndRefreshDatabase:
            "Delete and Refresh"
        }
    }
}

struct LibraryMaintenanceMenu: View {
    var body: some View {
        Menu {
            LibraryMaintenanceMenuItems()
        } label: {
            Text("Library")
        }
        .accessibilityIdentifier("library-maintenance-menu")
        .help("Library")
    }
}

struct LibraryMaintenanceMenuItems: View {
    @Environment(GrimoraAppModel.self) private var model
    @Environment(GrimoraLibraryMaintenanceController.self) private var maintenance

    var body: some View {
        Section("Database") {
            Button {
                Task { await model.checkForUpdates() }
            } label: {
                Text("Check for Updates")
            }
            .accessibilityIdentifier("check-updates-button")
            .disabled(model.isWorking)

            Button {
                Task { await model.importAvailableUpdate() }
            } label: {
                Text("Import Available Update")
            }
            .accessibilityIdentifier("import-available-update-button")
            .disabled(model.updateManifest == nil || model.isWorking)

            Button {
                Task { await model.refreshCardDatabase() }
            } label: {
                Text("Refresh Card Database")
            }
            .accessibilityIdentifier("refresh-card-database-button")
            .disabled(model.isWorking)

            if !model.usesManagedCatalog {
                Button {
                    Task { await model.refreshCardValues() }
                } label: {
                    Text("Refresh Card Values")
                }
                .accessibilityIdentifier("refresh-card-values-button")
                .disabled(model.isWorking || !model.hasLibrary)
            }
        }

        Section("Storage") {
            Button(role: .destructive) {
                maintenance.confirm(.deleteImages)
            } label: {
                Text("Delete Cached Images")
            }
            .accessibilityIdentifier("delete-cached-images-button")
            .disabled(model.isWorking)

            Button(role: .destructive) {
                maintenance.confirm(.deleteAndRefreshDatabase)
            } label: {
                Text("Delete and Refresh Database")
            }
            .accessibilityIdentifier("delete-and-refresh-database-button")
            .disabled(model.isWorking)
        }
    }
}

struct LibraryMaintenanceConfirmationDialog: ViewModifier {
    @Environment(GrimoraAppModel.self) private var model
    var controller: GrimoraLibraryMaintenanceController

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                controller.pendingConfirmation?.title ?? "Library",
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                if let confirmation = controller.pendingConfirmation {
                    Button(confirmation.confirmationTitle, role: .destructive) {
                        Task {
                            await perform(confirmation)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                if let confirmation = controller.pendingConfirmation {
                    Text(confirmation.message)
                }
            }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            controller.pendingConfirmation != nil
        } set: { isPresented in
            if !isPresented {
                controller.pendingConfirmation = nil
            }
        }
    }

    private func perform(_ confirmation: LibraryMaintenanceConfirmation) async {
        controller.pendingConfirmation = nil
        switch confirmation {
        case .deleteImages:
            await model.deleteCachedImages()
        case .deleteAndRefreshDatabase:
            await model.deleteAndRefreshCardDatabase()
        }
    }
}

extension View {
    func libraryMaintenanceConfirmationDialog(
        controller: GrimoraLibraryMaintenanceController
    ) -> some View {
        modifier(LibraryMaintenanceConfirmationDialog(controller: controller))
    }
}

public struct GrimoraLibraryCommands: Commands {
    @FocusedValue(\.appModel) private var model: GrimoraAppModel?
    @FocusedValue(\.libraryMaintenanceController) private var maintenance: GrimoraLibraryMaintenanceController?

    public init() {}

    public var body: some Commands {
        CommandMenu("Library") {
            Button("Check for Updates") {
                Task { await model?.checkForUpdates() }
            }
            .disabled(model?.isWorking != false)

            Button("Import Available Update") {
                Task { await model?.importAvailableUpdate() }
            }
            .disabled(model?.updateManifest == nil || model?.isWorking != false)

            Button("Refresh Card Database") {
                Task { await model?.refreshCardDatabase() }
            }
            .disabled(model?.isWorking != false)

            if model?.usesManagedCatalog == false {
                Button("Refresh Card Values") {
                    Task { await model?.refreshCardValues() }
                }
                .disabled(model?.isWorking != false || model?.hasLibrary != true)
            }

            Divider()

            Button("Delete Cached Images") {
                maintenance?.confirm(.deleteImages)
            }
            .disabled(model?.isWorking != false || maintenance == nil)

            Button("Delete and Refresh Database") {
                maintenance?.confirm(.deleteAndRefreshDatabase)
            }
            .disabled(model?.isWorking != false || maintenance == nil)
        }
    }
}
