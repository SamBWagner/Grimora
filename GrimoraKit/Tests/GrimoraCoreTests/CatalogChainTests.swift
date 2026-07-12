import Foundation
import Testing
@testable import GrimoraCore

/// Unit tests for the client's chain-walking decision: which deltas to apply, and when to give up
/// and fall back to a full download.
struct CatalogChainTests {
  @Test
  func singleStepPathWhenOneBuildBehind() {
    let chain = makeChain(["v1", "v2", "v3"])
    let path = chain.deltaPath(from: "v2")
    #expect(path?.count == 1)
    #expect(path?.first?.baseVersion == "v2")
  }

  @Test
  func multiStepPathWhenSeveralBuildsBehind() {
    let chain = makeChain(["v1", "v2", "v3"])
    let path = chain.deltaPath(from: "v1")
    #expect(path?.map(\.baseVersion) == ["v1", "v2"])
  }

  @Test
  func emptyPathWhenAlreadyCurrent() {
    let chain = makeChain(["v1", "v2", "v3"])
    #expect(chain.deltaPath(from: "v3") == [])
  }

  @Test
  func nilWhenInstalledVersionNotInChain() {
    let chain = makeChain(["v1", "v2", "v3"])
    #expect(chain.deltaPath(from: "v0-expired") == nil)
  }

  @Test
  func nilWhenChainHasAGap() {
    // v3 has no delta from v2 → a client on v1 or v2 cannot walk forward.
    var chain = makeChain(["v1", "v2", "v3"])
    chain.entries[2].deltaFromPrevious = nil
    #expect(chain.deltaPath(from: "v2") == nil)
    #expect(chain.deltaPath(from: "v1") == nil)
  }

  @Test
  func nilWhenSchemaVersionChangesAlongWalk() {
    var chain = makeChain(["v1", "v2", "v3"])
    chain.entries[2].catalogSchemaVersion = CatalogManifest.currentSchemaVersion + 1
    #expect(chain.deltaPath(from: "v1") == nil)
  }

  @Test
  func nilWhenDeltaFormatIsUnrecognized() {
    var chain = makeChain(["v1", "v2"])
    chain.entries[1].deltaFromPrevious?.formatVersion = CatalogDelta.currentFormatVersion + 1
    #expect(chain.deltaPath(from: "v1") == nil)
  }

  private func makeChain(_ versions: [String]) -> CatalogChain {
    let digests = CatalogContentDigests(
      cards: "c", cardFaces: "f", series: "s", summaries: "u", mappings: "m", overall: "o"
    )
    let entries = versions.enumerated().map { index, version -> CatalogChainEntry in
      let delta = index == 0
        ? nil
        : CatalogDeltaDescriptor(
            baseVersion: versions[index - 1],
            url: URL(string: "https://example.test/v1/catalog/\(version)/delta/\(versions[index - 1])")!,
            sha256: "deadbeef",
            bytes: 1024,
            formatVersion: CatalogDelta.currentFormatVersion
          )
      return CatalogChainEntry(
        version: version,
        catalogSchemaVersion: CatalogManifest.currentSchemaVersion,
        contentDigests: digests,
        deltaFromPrevious: delta
      )
    }
    return CatalogChain(current: versions.last ?? "", entries: entries)
  }
}
