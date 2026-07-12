import Foundation
import Hummingbird

protocol CatalogObjectServing: Sendable {
  func currentManifestData() async throws -> Data
  func currentChainData() async throws -> Data
  func redirectResponse(version: String) async throws -> Response
  func deltaRedirectResponse(version: String, base: String) async throws -> Response
  func verifyReady() async throws
}

func makeCatalogRouter(
  storage: any CatalogObjectServing
) -> Router<BasicRequestContext> {
  let router = Router()
  router.get("/v1/catalog") { _, _ -> Response in
    let data = try await storage.currentManifestData()
    return Response(
      status: .ok,
      headers: [
        .cacheControl: "public, max-age=60, must-revalidate",
        .contentType: "application/json",
      ],
      body: .init(byteBuffer: ByteBuffer(bytes: data))
    )
  }
  // Registered before `/:version` so the literal "chain" segment wins over the parameter.
  router.get("/v1/catalog/chain") { _, _ -> Response in
    let data = try await storage.currentChainData()
    return Response(
      status: .ok,
      headers: [
        .cacheControl: "public, max-age=60, must-revalidate",
        .contentType: "application/json",
      ],
      body: .init(byteBuffer: ByteBuffer(bytes: data))
    )
  }
  router.get("/v1/catalog/:version/delta/:base") { _, context -> Response in
    let version = try context.parameters.require("version")
    let base = try context.parameters.require("base")
    return try await storage.deltaRedirectResponse(version: version, base: base)
  }
  router.head("/v1/catalog/:version/delta/:base") { _, context -> Response in
    let version = try context.parameters.require("version")
    let base = try context.parameters.require("base")
    return try await storage.deltaRedirectResponse(version: version, base: base).createHeadResponse()
  }
  router.get("/v1/catalog/:version") { _, context -> Response in
    let version = try context.parameters.require("version")
    return try await storage.redirectResponse(version: version)
  }
  router.head("/v1/catalog/:version") { _, context -> Response in
    let version = try context.parameters.require("version")
    return try await storage.redirectResponse(version: version).createHeadResponse()
  }
  router.get("/health/live") { _, _ -> HTTPResponse.Status in
    .ok
  }
  router.get("/health/ready") { _, _ -> HTTPResponse.Status in
    do {
      try await storage.verifyReady()
      return .ok
    } catch {
      return .serviceUnavailable
    }
  }
  return router
}
