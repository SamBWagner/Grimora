import Foundation
import GrimoraCore
import Hummingbird
import SotoS3

enum CatalogAPIConfigurationError: Error {
  case missing(String)
  case invalidVersion
}

final class TigrisCatalogStorage: CatalogObjectServing, @unchecked Sendable {
  struct ObjectLocation: Equatable {
    var bucket: String
    var key: String
  }

  private let artifactsBucket: String
  private let metadataBucket: String
  private let endpoint: String
  private let client: AWSClient
  private let s3: S3

  init(environment: [String: String]) throws {
    guard let artifactsBucket = environment["TIGRIS_ARTIFACTS_BUCKET"],
      !artifactsBucket.isEmpty
    else {
      throw CatalogAPIConfigurationError.missing("TIGRIS_ARTIFACTS_BUCKET")
    }
    guard let metadataBucket = environment["TIGRIS_METADATA_BUCKET"],
      !metadataBucket.isEmpty
    else {
      throw CatalogAPIConfigurationError.missing("TIGRIS_METADATA_BUCKET")
    }
    let accessKey = environment["TIGRIS_ACCESS_KEY_ID"] ?? environment["AWS_ACCESS_KEY_ID"]
    let secretKey = environment["TIGRIS_SECRET_ACCESS_KEY"] ?? environment["AWS_SECRET_ACCESS_KEY"]
    guard let accessKey, let secretKey else {
      throw CatalogAPIConfigurationError.missing("Tigris read credentials")
    }

    self.artifactsBucket = artifactsBucket
    self.metadataBucket = metadataBucket
    endpoint = environment["TIGRIS_ENDPOINT"] ?? "https://fly.storage.tigris.dev"
    client = AWSClient(
      credentialProvider: .static(
        accessKeyId: accessKey,
        secretAccessKey: secretKey
      )
    )
    s3 = S3(
      client: client,
      region: Region(rawValue: environment["TIGRIS_REGION"] ?? "auto"),
      endpoint: endpoint
    )
  }

  func currentManifestData() async throws -> Data {
    let output = try await s3.getObject(bucket: metadataBucket, key: "current.json")
    let buffer = try await output.body.collect(upTo: 2 * 1024 * 1024)
    return Data(buffer.readableBytesView)
  }

  func currentChainData() async throws -> Data {
    let output = try await s3.getObject(bucket: metadataBucket, key: "chain.json")
    let buffer = try await output.body.collect(upTo: 16 * 1024 * 1024)
    return Data(buffer.readableBytesView)
  }

  func deltaRedirectResponse(version: String, base: String) async throws -> Response {
    guard Self.isValidVersion(version), Self.isValidVersion(base) else {
      throw HTTPError(.badRequest)
    }
    let location = Self.deltaObjectLocation(
      version: version,
      base: base,
      artifactsBucket: artifactsBucket
    )
    _ = try await s3.headObject(bucket: location.bucket, key: location.key)
    let unsignedURL = URL(string: endpoint)!
      .appendingPathComponent(location.bucket)
      .appendingPathComponent(location.key)
    let signedURL = try await s3.signURL(
      url: unsignedURL,
      httpMethod: .GET,
      expires: .minutes(10)
    )
    var response = Response.redirect(to: signedURL.absoluteString, type: .temporary)
    response.headers[.cacheControl] = "private, max-age=60"
    return response
  }

  func redirectResponse(version: String) async throws -> Response {
    guard Self.isValidVersion(version) else {
      throw HTTPError(.badRequest)
    }
    let currentData = try await currentManifestData()
    let current = try CatalogManifest.decoder().decode(CatalogManifest.self, from: currentData)
    let location = Self.objectLocation(
      requestedVersion: version,
      currentVersion: current.version,
      artifactsBucket: artifactsBucket,
      metadataBucket: metadataBucket
    )
    _ = try await s3.headObject(bucket: location.bucket, key: location.key)
    let unsignedURL = URL(string: endpoint)!
      .appendingPathComponent(location.bucket)
      .appendingPathComponent(location.key)
    let signedURL = try await s3.signURL(
      url: unsignedURL,
      httpMethod: .GET,
      expires: .minutes(10)
    )
    var response = Response.redirect(to: signedURL.absoluteString, type: .temporary)
    response.headers[.cacheControl] = "private, max-age=60"
    return response
  }

  func verifyReady() async throws {
    let data = try await currentManifestData()
    _ = try CatalogManifest.decoder().decode(CatalogManifest.self, from: data)
    _ = try await s3.headObject(
      bucket: metadataBucket,
      key: "current/catalog.sqlite.gz"
    )
  }

  func shutdown() async throws {
    try await client.shutdown()
  }

  private static func isValidVersion(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 100
      && value.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._")).contains($0)
      }
  }

  static func objectLocation(
    requestedVersion: String,
    currentVersion: String,
    artifactsBucket: String,
    metadataBucket: String
  ) -> ObjectLocation {
    if requestedVersion == currentVersion {
      return ObjectLocation(
        bucket: metadataBucket,
        key: "current/catalog.sqlite.gz"
      )
    }
    return ObjectLocation(
      bucket: artifactsBucket,
      key: "catalogs/\(requestedVersion)/catalog.sqlite.gz"
    )
  }

  /// Deltas are always immutable siblings of the target version's artifact — never the mutable
  /// `current` pointer — so they always resolve to the artifacts bucket.
  static func deltaObjectLocation(
    version: String,
    base: String,
    artifactsBucket: String
  ) -> ObjectLocation {
    ObjectLocation(
      bucket: artifactsBucket,
      key: "catalogs/\(version)/delta-from-\(base).sqlite.gz"
    )
  }
}
