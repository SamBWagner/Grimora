import Foundation
import GrimoraCore
import SotoS3

public struct TigrisConfiguration: Sendable {
  public var artifactsBucket: String
  public var metadataBucket: String
  public var endpoint: String
  public var region: Region
  public var credentials: TigrisCredentials

  public init(environment: [String: String]) throws {
    guard let artifactsBucket = environment["TIGRIS_ARTIFACTS_BUCKET"],
      !artifactsBucket.isEmpty
    else {
      throw EngineError.missingConfiguration("TIGRIS_ARTIFACTS_BUCKET")
    }
    guard let metadataBucket = environment["TIGRIS_METADATA_BUCKET"],
      !metadataBucket.isEmpty
    else {
      throw EngineError.missingConfiguration("TIGRIS_METADATA_BUCKET")
    }
    self.artifactsBucket = artifactsBucket
    self.metadataBucket = metadataBucket
    endpoint = environment["TIGRIS_ENDPOINT"] ?? "https://fly.storage.tigris.dev"
    region = Region(rawValue: environment["TIGRIS_REGION"] ?? "auto")
    credentials = try KeychainCredentials.load(environment: environment)
  }
}

public struct TigrisPublisher {
  public let configuration: TigrisConfiguration

  public init(configuration: TigrisConfiguration) {
    self.configuration = configuration
  }

  /// Publishes the artifact + manifest to Tigris.
  ///
  /// - Parameter progress: optional callback reporting `(fraction, label)` as each large object
  ///   uploads, where `fraction` is 0...1 for the current upload.
  public func publish(
    manifest: CatalogManifest,
    artifactURL: URL,
    manifestURL: URL,
    progress: (@Sendable (Double, String) async -> Void)? = nil
  ) async throws {
    let client = AWSClient(
      credentialProvider: .static(
        accessKeyId: configuration.credentials.accessKeyID,
        secretAccessKey: configuration.credentials.secretAccessKey
      )
    )
    // The default Soto per-request timeout is 20s, far too short for uploading a multi-megabyte
    // catalog over a home uplink — a part upload that exceeds it throws HTTPClientError.deadlineExceeded.
    let s3 = S3(
      client: client,
      region: configuration.region,
      endpoint: configuration.endpoint,
      timeout: .seconds(600)
    )
    do {
      let prefix = "catalogs/\(manifest.version)"
      let artifactRequest = S3.CreateMultipartUploadRequest(
        bucket: configuration.artifactsBucket,
        cacheControl: "public, max-age=31536000, immutable",
        contentType: "application/gzip",
        key: "\(prefix)/catalog.sqlite.gz"
      )
      _ = try await s3.multipartUpload(
        artifactRequest,
        filename: artifactURL.path,
        concurrentUploads: 3,
        abortOnFail: true
      ) { fraction in
        await progress?(fraction, "Uploading catalog")
      }

      let manifestData = try Data(contentsOf: manifestURL)
      _ = try await s3.putObject(
        body: AWSHTTPBody(bytes: manifestData),
        bucket: configuration.artifactsBucket,
        cacheControl: "public, max-age=31536000, immutable",
        contentType: "application/json",
        ifNoneMatch: "*",
        key: "\(prefix)/manifest.json"
      )

      let currentArtifactRequest = S3.CreateMultipartUploadRequest(
        bucket: configuration.metadataBucket,
        cacheControl: "public, max-age=60, must-revalidate",
        contentType: "application/gzip",
        key: "current/catalog.sqlite.gz"
      )
      _ = try await s3.multipartUpload(
        currentArtifactRequest,
        filename: artifactURL.path,
        concurrentUploads: 3,
        abortOnFail: true
      ) { fraction in
        await progress?(fraction, "Updating current pointer")
      }

      _ = try await s3.putObject(
        body: AWSHTTPBody(bytes: manifestData),
        bucket: configuration.metadataBucket,
        cacheControl: "public, max-age=60, must-revalidate",
        contentType: "application/json",
        key: "current.json"
      )
    } catch {
      try? await client.shutdown()
      throw error
    }
    try await client.shutdown()
  }
}
