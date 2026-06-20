import Foundation
import GrimoraCore
import Testing
@testable import GrimoraDataEngine

@Test
func processLockPreventsConcurrentRuns() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("EngineLockTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("engine.lock")

  let first = try ProcessLock(url: url)
  _ = withExtendedLifetime(first) {
    #expect(throws: ProcessLockError.alreadyRunning) {
      _ = try ProcessLock(url: url)
    }
  }
}

@Test
func stateRoundTripsAndEnvironmentCredentialsAvoidKeychain() throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("engine-state-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  let state = EngineState(
    lastSuccessfulSources: nil,
    lastBuiltManifestPath: "/tmp/manifest.json",
    lastPublishedVersion: "v1-test",
    lastRunAt: Date(timeIntervalSince1970: 100),
    lastError: nil
  )
  try state.save(to: url)
  #expect(EngineState.load(from: url) == state)

  let credentials = try KeychainCredentials.load(environment: [
    "TIGRIS_ACCESS_KEY_ID": "access",
    "TIGRIS_SECRET_ACCESS_KEY": "secret",
  ])
  #expect(credentials.accessKeyID == "access")
  #expect(credentials.secretAccessKey == "secret")
}

@Test
func launchAgentRunsAtLoginAndEverySixHours() throws {
  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let plistURL = packageRoot
    .appendingPathComponent("Resources/com.samwagner.GrimoraDataEngine.plist")
  let data = try Data(contentsOf: plistURL)
  let plist = try #require(
    PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
  )
  #expect(plist["RunAtLoad"] as? Bool == true)
  #expect(plist["StandardOutPath"] as? String == "__LOG_DIR__/launch-agent.log")
  #expect(plist["StandardErrorPath"] as? String == "__LOG_DIR__/launch-agent-error.log")
  let schedules = try #require(plist["StartCalendarInterval"] as? [[String: Int]])
  #expect(schedules.map { $0["Hour"] ?? -1 } == [0, 6, 12, 18])
  let environment = try #require(plist["EnvironmentVariables"] as? [String: String])
  #expect(environment["TIGRIS_ARTIFACTS_BUCKET"] == "__ARTIFACTS_BUCKET__")
  #expect(environment["TIGRIS_METADATA_BUCKET"] == "__METADATA_BUCKET__")
  #expect(environment["GRIMORA_CATALOG_PUBLIC_BASE_URL"] == "__CATALOG_PUBLIC_BASE_URL__")
}

@Test
func tigrisConfigurationRequiresSeparateBuckets() throws {
  let configuration = try TigrisConfiguration(environment: [
    "TIGRIS_ARTIFACTS_BUCKET": "history",
    "TIGRIS_METADATA_BUCKET": "metadata",
    "TIGRIS_ACCESS_KEY_ID": "access",
    "TIGRIS_SECRET_ACCESS_KEY": "secret",
  ])
  #expect(configuration.artifactsBucket == "history")
  #expect(configuration.metadataBucket == "metadata")
  #expect(configuration.endpoint == "https://fly.storage.tigris.dev")
}

@Test
func catalogVersionIncludesArtifactPipelineAndEnrichmentIdentity() throws {
  let sources = CatalogSourceVersions(
    scryfallUpdatedAt: "2026-06-14",
    mtgjsonDate: "2026-06-14",
    mtgjsonVersion: "5.3.0"
  )
  let baseline = try CatalogVersioning.contentVersion(
    sources: sources,
    enrichments: [],
    artifactSHA256: "artifact-a",
    pipelineVersion: 1
  )
  let same = try CatalogVersioning.contentVersion(
    sources: sources,
    enrichments: [],
    artifactSHA256: "artifact-a",
    pipelineVersion: 1
  )
  let changedArtifact = try CatalogVersioning.contentVersion(
    sources: sources,
    enrichments: [],
    artifactSHA256: "artifact-b",
    pipelineVersion: 1
  )
  let changedPipeline = try CatalogVersioning.contentVersion(
    sources: sources,
    enrichments: [],
    artifactSHA256: "artifact-a",
    pipelineVersion: 2
  )
  let changedEnrichment = try CatalogVersioning.contentVersion(
    sources: sources,
    enrichments: [.init(identifier: "ai-tags", version: 1)],
    artifactSHA256: "artifact-a",
    pipelineVersion: 1
  )
  #expect(baseline == same)
  #expect(baseline != changedArtifact)
  #expect(baseline != changedPipeline)
  #expect(baseline != changedEnrichment)
}
