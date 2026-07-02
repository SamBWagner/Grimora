import Foundation
import GrimoraCore

/// The harness's stripped-down take on `GrimoraEnvironment.live()`: the managed
/// catalog database, image cache, and update service — no cloud sync, currency,
/// or search stores. Runs in its own sandbox (com.samwagner.GrimoraScry), so the
/// catalog is downloaded on first launch rather than shared with the main app.
struct HarnessEnvironment: Sendable {
  var database: CardDatabase
  var updateService: LibraryUpdateService
  var importer: LibraryImporter
  var imageCache: CardImageCache
  var temporaryDirectory: URL

  static func live(fileManager: FileManager = .default) throws -> HarnessEnvironment {
    let base = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let supportDirectory = base.appendingPathComponent("GrimoraScry", isDirectory: true)
    let imageDirectory = supportDirectory.appendingPathComponent("Images", isDirectory: true)
    let temporaryDirectory = fileManager.temporaryDirectory
      .appendingPathComponent("GrimoraScry", isDirectory: true)
    for directory in [supportDirectory, imageDirectory, temporaryDirectory] {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let network = URLSessionNetworkClient()
    let bulkClient = BulkDataClient(
      network: network,
      catalogAPIURL: URL(string: "https://grimora-data-api.fly.dev/v1/catalog")
    )
    let bootstrap = try ManagedCatalogMigrationService.bootstrap(
      supportDirectory: supportDirectory,
      bulkDataClient: bulkClient,
      fileManager: fileManager
    )
    let imageStore = ImageStore(rootDirectory: imageDirectory)
    let imageResolver = DownloadingImageResolver(store: imageStore, network: network)
    return HarnessEnvironment(
      database: bootstrap.database,
      updateService: LibraryUpdateService(
        database: bootstrap.database,
        bulkDataClient: bulkClient
      ),
      importer: LibraryImporter(database: bootstrap.database, imageResolver: imageResolver),
      imageCache: CardImageCache(database: bootstrap.database, imageResolver: imageResolver),
      temporaryDirectory: temporaryDirectory
    )
  }
}
