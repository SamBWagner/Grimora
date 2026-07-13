import Foundation
import Hummingbird
import SotoS3

@main
enum GrimoraDataAPIMain {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    let storage = try TigrisCatalogStorage(environment: environment)
    let router = makeCatalogRouter(storage: storage)

    let port = Int(environment["PORT"] ?? "8080") ?? 8080
    let app = Application(
      router: router,
      configuration: .init(address: .hostname("0.0.0.0", port: port))
    )
    do {
      try await app.runService()
      try await storage.shutdown()
    } catch {
      try? await storage.shutdown()
      throw error
    }
  }
}
