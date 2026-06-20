import Foundation
import GrimoraCore

extension GrimoraAppModel {
  public var isManagedCatalogMigrationInProgress: Bool {
    switch managedCatalogMigrationStatus {
    case .checking, .downloading, .validating:
      true
    case .restartRequired, .failed, .none:
      false
    }
  }

  public func stageManagedCatalogMigration(manual: Bool = true) async {
    guard let managedCatalogMigrationService else {
      return
    }
    guard managedCatalogMigrationTask == nil else {
      return
    }

    let task = Task { [weak self, managedCatalogMigrationService] in
      do {
        _ = try await managedCatalogMigrationService.stageLatestCatalog(
          manual: manual
        ) { status in
          await MainActor.run {
            self?.managedCatalogMigrationStatus = status
            self?.statusMessage = Self.catalogMigrationMessage(status)
          }
        }
      } catch let error as ManagedCatalogMigrationError {
        let message: String
        switch error {
        case .invalidManifest:
          message = "The Grimora catalog service returned an invalid manifest."
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
          message =
            "The catalog needs \(Self.byteCountFormatter.string(fromByteCount: requiredBytes)) free; "
            + "\(Self.byteCountFormatter.string(fromByteCount: availableBytes)) is available."
        }
        self?.managedCatalogMigrationStatus = .failed(message)
        self?.statusMessage = message
      } catch {
        let message = "The managed catalog could not be staged. Your current library is still available."
        self?.managedCatalogMigrationStatus = .failed(message)
        self?.statusMessage = message
      }
    }
    managedCatalogMigrationTask = task
    await task.value
    managedCatalogMigrationTask = nil
  }

  private static func catalogMigrationMessage(
    _ status: ManagedCatalogMigrationStatus
  ) -> String {
    switch status {
    case .checking:
      "Checking the managed Grimora catalog..."
    case .downloading(let completedBytes, let totalBytes):
      byteProgressDetail(completedBytes: completedBytes, totalBytes: totalBytes)
        ?? "Downloading the managed Grimora catalog..."
    case .validating:
      "Validating the managed Grimora catalog..."
    case .restartRequired:
      "The managed catalog is ready. Quit and reopen Grimora to finish upgrading."
    case .failed(let message):
      message
    }
  }
}
