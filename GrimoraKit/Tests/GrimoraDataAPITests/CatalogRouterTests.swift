import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import GrimoraDataAPI

@Test
func catalogRoutesServeManifestRedirectsAndHealth() async throws {
  let storage = StubCatalogStorage()
  let app = Application(router: makeCatalogRouter(storage: storage))
  try await app.test(.router) { client in
    try await client.execute(uri: "/health/live", method: .get) {
      #expect($0.status == .ok)
    }
    try await client.execute(uri: "/health/ready", method: .get) {
      #expect($0.status == .ok)
    }
    try await client.execute(uri: "/v1/catalog", method: .get) {
      #expect($0.status == .ok)
      #expect($0.headers[.cacheControl] == "public, max-age=60, must-revalidate")
      #expect(String(buffer: $0.body) == #"{"version":"stale-but-readable"}"#)
    }
    try await client.execute(uri: "/v1/catalog/v1-test", method: .get) {
      #expect($0.status == .temporaryRedirect)
      #expect($0.headers[.location] == "https://example.test/catalog.sqlite.gz")
    }
    try await client.execute(uri: "/v1/catalog/v1-test", method: .head) {
      #expect($0.status == .temporaryRedirect)
      #expect($0.body.readableBytes == 0)
    }
  }
}

@Test
func readinessFailsWhenManifestOrArtifactIsMissing() async throws {
  let storage = StubCatalogStorage(isReady: false)
  let app = Application(router: makeCatalogRouter(storage: storage))
  try await app.test(.router) { client in
    try await client.execute(uri: "/health/ready", method: .get) {
      #expect($0.status == .serviceUnavailable)
    }
  }
}

@Test
func currentVersionUsesDurableMetadataBucketAndHistoryUsesExpiringBucket() {
  #expect(
    TigrisCatalogStorage.objectLocation(
      requestedVersion: "v1-current",
      currentVersion: "v1-current",
      artifactsBucket: "history",
      metadataBucket: "metadata"
    )
      == .init(bucket: "metadata", key: "current/catalog.sqlite.gz")
  )
  #expect(
    TigrisCatalogStorage.objectLocation(
      requestedVersion: "v1-old",
      currentVersion: "v1-current",
      artifactsBucket: "history",
      metadataBucket: "metadata"
    )
      == .init(bucket: "history", key: "catalogs/v1-old/catalog.sqlite.gz")
  )
}

private struct StubCatalogStorage: CatalogObjectServing {
  var isReady = true

  func currentManifestData() async throws -> Data {
    Data(#"{"version":"stale-but-readable"}"#.utf8)
  }

  func redirectResponse(version: String) async throws -> Response {
    Response.redirect(to: "https://example.test/catalog.sqlite.gz", type: .temporary)
  }

  func verifyReady() async throws {
    if !isReady {
      throw HTTPError(.notFound)
    }
  }
}
