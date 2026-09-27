import Foundation
import GrimoraCore
import GrimoraEngineKit
import Testing

private enum SemanticPublicationEvidenceError: Error, Equatable {
  case invalidConfiguration(String)
  case invalidInput(String)
  case verificationFailed(String)
}

private struct SemanticPublicationEvidenceConfiguration: Equatable {
  let baseDirectory: URL
  let outputDirectory: URL
  let repositoryRoot: URL
  let baseBuildWallSeconds: Double?

  static func from(
    environment: [String: String],
    repositoryRoot: URL
  ) throws -> Self? {
    guard let rawEnable = environment["GRIMORA_SEMANTIC_PUBLICATION_ENABLED"] else {
      return nil
    }
    guard rawEnable.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "GRIMORA_SEMANTIC_PUBLICATION_ENABLED must be 1"
      )
    }
    let basePath = environment["GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let outputPath = environment["GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let hasBase = !(basePath?.isEmpty ?? true)
    let hasOutput = !(outputPath?.isEmpty ?? true)

    guard hasBase, hasOutput, let basePath, let outputPath else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "Set both GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR and GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR"
      )
    }

    let baseBuildWallSeconds: Double?
    if let raw = environment["GRIMORA_SEMANTIC_PUBLICATION_BASE_BUILD_SECONDS"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    {
      guard let value = Double(raw), value.isFinite, value >= 0 else {
        throw SemanticPublicationEvidenceError.invalidConfiguration(
          "GRIMORA_SEMANTIC_PUBLICATION_BASE_BUILD_SECONDS must be a nonnegative number"
        )
      }
      baseBuildWallSeconds = value
    } else {
      baseBuildWallSeconds = nil
    }

    let baseDirectory = URL(fileURLWithPath: basePath, isDirectory: true).standardizedFileURL
    let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
    let root = repositoryRoot.standardizedFileURL
    guard outputDirectory.path.hasPrefix(root.path + "/") else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR must be inside the repository"
      )
    }
    guard !outputDirectory.path.hasPrefix(baseDirectory.path + "/"),
      !baseDirectory.path.hasPrefix(outputDirectory.path + "/"),
      outputDirectory != baseDirectory
    else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "Base and output directories must not overlap"
      )
    }
    return Self(
      baseDirectory: baseDirectory,
      outputDirectory: outputDirectory,
      repositoryRoot: root,
      baseBuildWallSeconds: baseBuildWallSeconds
    )
  }
}

private struct SemanticPublicationMutationChain {
  static let addedTagID = "job-b-evidence:controlled-added-tag"
  static let addedSource = "job-b-semantic-publication-evidence@1"

  let b: SemanticCatalogSnapshot
  let c: SemanticCatalogSnapshot
  let renamedTagID: String
  let weightedMembershipCardKey: SemanticCardKey

  static func make(
    from snapshotA: SemanticCatalogSnapshot,
    idfCardCount: Int
  ) throws -> Self {
    guard idfCardCount > 0 else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "The real catalog must contain at least one semantic membership card"
      )
    }
    guard !snapshotA.tags.contains(where: { $0.id == addedTagID }) else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "The catalog already contains the reserved evidence tag identifier"
      )
    }
    guard let selectedMembership = snapshotA.cardTags.sorted(by: cardTagOrder).first,
      snapshotA.tags.contains(where: { $0.id == selectedMembership.tagID })
    else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "The real catalog must contain at least one valid semantic membership"
      )
    }

    let renamedTagID = selectedMembership.tagID
    var b = snapshotA
    guard let renamedIndex = b.tags.firstIndex(where: { $0.id == renamedTagID }),
      let membershipIndex = b.cardTags.firstIndex(where: {
        $0.cardKey == selectedMembership.cardKey
          && $0.tagID == selectedMembership.tagID
          && $0.source == selectedMembership.source
      })
    else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "Unable to select deterministic semantic mutation records"
      )
    }

    b.tags[renamedIndex].label += " [Job B evidence B]"
    b.tags[renamedIndex].description = "Controlled Job B publication-evidence update."
    b.cardTags[membershipIndex].weightMillis =
      selectedMembership.weightMillis == 777 ? 778 : 777
    b.tags.append(
      SemanticTagRecord(
        id: addedTagID,
        namespace: "job-b-evidence",
        slug: "controlled-added-tag",
        label: "Controlled Added Tag",
        description: "Synthetic semantic tag used only in private publication evidence.",
        similarityEnabled: true,
        source: addedSource
      )
    )
    b.aliases.append(
      SemanticTagAliasRecord(
        tagID: addedTagID,
        alias: "Job B Controlled Added Tag",
        aliasKey: SemanticTagAliasRecord.normalizedKey(for: "Job B Controlled Added Tag")
      )
    )
    b.edges.append(
      SemanticTagEdgeRecord(parentTagID: renamedTagID, childTagID: addedTagID)
    )
    b.cardTags.append(
      SemanticCardTagRecord(
        cardKey: selectedMembership.cardKey,
        tagID: addedTagID,
        weightMillis: 925,
        annotation: "Controlled Job B add mutation",
        source: addedSource
      )
    )
    b = normalized(b, idfCardCount: idfCardCount)

    var c = b
    if let renamedIndex = c.tags.firstIndex(where: { $0.id == renamedTagID }) {
      c.tags[renamedIndex].label = c.tags[renamedIndex].label
        .replacingOccurrences(of: " [Job B evidence B]", with: " [Job B evidence C]")
      c.tags[renamedIndex].description = "Controlled Job B publication-evidence follow-up update."
    }
    c.tags.removeAll { $0.id == addedTagID }
    c.aliases.removeAll { $0.tagID == addedTagID }
    c.edges.removeAll { $0.parentTagID == addedTagID || $0.childTagID == addedTagID }
    c.cardTags.removeAll { $0.tagID == addedTagID }
    c = normalized(c, idfCardCount: idfCardCount)

    return Self(
      b: b,
      c: c,
      renamedTagID: renamedTagID,
      weightedMembershipCardKey: selectedMembership.cardKey
    )
  }

  private static func normalized(
    _ snapshot: SemanticCatalogSnapshot,
    idfCardCount: Int
  ) -> SemanticCatalogSnapshot {
    var result = snapshot
    result.tags.sort { $0.id < $1.id }
    result.aliases.sort {
      ($0.tagID, $0.aliasKey) < ($1.tagID, $1.aliasKey)
    }
    result.edges.sort {
      ($0.parentTagID, $0.childTagID) < ($1.parentTagID, $1.childTagID)
    }
    result.cardTags.sort(by: cardTagOrder)
    result.stats = recomputeStatistics(for: result, idfCardCount: idfCardCount)
    return result
  }

  private static func recomputeStatistics(
    for snapshot: SemanticCatalogSnapshot,
    idfCardCount: Int
  ) -> [SemanticTagStatsRecord] {
    var directCards: [String: Set<SemanticCardKey>] = [:]
    for membership in snapshot.cardTags {
      directCards[membership.tagID, default: []].insert(membership.cardKey)
    }
    var childrenByParent: [String: Set<String>] = [:]
    for edge in snapshot.edges {
      childrenByParent[edge.parentTagID, default: []].insert(edge.childTagID)
    }

    func descendants(of root: String) -> Set<String> {
      var pending = [root]
      var visited: Set<String> = []
      while let tagID = pending.popLast() {
        guard visited.insert(tagID).inserted else { continue }
        pending.append(contentsOf: childrenByParent[tagID, default: []].sorted())
      }
      return visited
    }

    return snapshot.tags.sorted { $0.id < $1.id }.map { tag in
      let direct = directCards[tag.id, default: []]
      let effective = descendants(of: tag.id).reduce(into: Set<SemanticCardKey>()) {
        $0.formUnion(directCards[$1, default: []])
      }
      let inverseFrequencyMillis: Int
      if tag.similarityEnabled {
        let numerator = Double(idfCardCount + 1)
        let denominator = Double(effective.count + 1)
        inverseFrequencyMillis = max(
          0,
          Int(((log(numerator / denominator) + 1) * 1_000).rounded())
        )
      } else {
        inverseFrequencyMillis = 0
      }
      return SemanticTagStatsRecord(
        tagID: tag.id,
        directCardCount: direct.count,
        effectiveCardCount: effective.count,
        inverseFrequencyMillis: inverseFrequencyMillis
      )
    }
  }

  private static func cardTagOrder(
    _ lhs: SemanticCardTagRecord,
    _ rhs: SemanticCardTagRecord
  ) -> Bool {
    (lhs.cardKey.rawValue, lhs.tagID, lhs.source)
      < (rhs.cardKey.rawValue, rhs.tagID, rhs.source)
  }
}

private struct SemanticPublicationCatalogEvidence: Encodable {
  var label: String
  var version: String
  var generationKind: String
  var generationMilliseconds: Double?
  var logicalDigests: CatalogContentDigests
  var sqliteSHA256: String
  var gzipSHA256: String
  var uncompressedBytes: Int64
  var compressedBytes: Int64
  var semanticCounts: CatalogSemanticCounts
  var integrityCheck: String
  var duplicates: SemanticPublicationDuplicateCounts
  var orphans: SemanticPublicationOrphanCounts
  var manifestValidated: Bool
  var measurements: SemanticPublicationMeasurements
}

private struct SemanticPublicationDuplicateCounts: Encodable {
  var tagIDs: Int
  var sourceSlugs: Int
  var aliases: Int
  var edges: Int
  var memberships: Int
  var statistics: Int

  var total: Int {
    tagIDs + sourceSlugs + aliases + edges + memberships + statistics
  }
}

private struct SemanticPublicationOrphanCounts: Encodable {
  var aliases: Int
  var edgeParents: Int
  var edgeChildren: Int
  var membershipTags: Int
  var membershipCards: Int
  var statistics: Int

  var total: Int {
    aliases + edgeParents + edgeChildren + membershipTags + membershipCards + statistics
  }
}

private struct SemanticPublicationMeasurement: Encodable {
  var identifier: String
  var resultCount: Int
  var milliseconds: Double
}

private struct SemanticPublicationMeasurements: Encodable {
  var cardToTag: SemanticPublicationMeasurement
  var tagToCard: SemanticPublicationMeasurement
  var ancestors: SemanticPublicationMeasurement
  var descendants: SemanticPublicationMeasurement
  var digestMilliseconds: Double
}

private struct SemanticPublicationDeltaStatsEvidence: Encodable {
  var cardFieldChanges: Int
  var cardsUpserted: Int
  var cardsDeleted: Int
  var cardFacesReplacedCards: Int
  var seriesSlid: Int
  var seriesReplaced: Int
  var seriesDeleted: Int
  var mappingsUpserted: Int
  var mappingsDeleted: Int
  var metadataSet: Int
  var semanticCatalogReplaced: Bool
  var semanticRowsReplaced: Int

  init(_ stats: CatalogDeltaStats) {
    cardFieldChanges = stats.cardFieldChanges
    cardsUpserted = stats.cardsUpserted
    cardsDeleted = stats.cardsDeleted
    cardFacesReplacedCards = stats.cardFacesReplacedCards
    seriesSlid = stats.seriesSlid
    seriesReplaced = stats.seriesReplaced
    seriesDeleted = stats.seriesDeleted
    mappingsUpserted = stats.mappingsUpserted
    mappingsDeleted = stats.mappingsDeleted
    metadataSet = stats.metadataSet
    semanticCatalogReplaced = stats.semanticCatalogReplaced
    semanticRowsReplaced = stats.semanticRowsReplaced
  }
}

private struct SemanticPublicationDeltaEvidence: Encodable {
  var fromVersion: String
  var toVersion: String
  var sqliteSHA256: String
  var gzipSHA256: String
  var uncompressedBytes: Int64
  var compressedBytes: Int64
  var uncompressedPercentOfTargetFullCompressed: Double
  var compressedPercentOfTargetFullCompressed: Double
  var buildMilliseconds: Double
  var applyMilliseconds: Double
  var stats: SemanticPublicationDeltaStatsEvidence
  var appliedDigestMatched: Bool
  var appliedManifestValidated: Bool
}

private struct SemanticPublicationChainEvidence: Encodable {
  var path: [String]
  var applyMilliseconds: Double
  var finalDigestMatched: Bool
  var finalManifestValidated: Bool
}

private struct SemanticPublicationMutationEvidence: Encodable {
  var transition: String
  var operations: [String]
}

private struct SemanticPublicationEvidenceReport: Encodable {
  var schemaVersion: Int
  var sourceBuildVersion: String
  var provenance: String
  var catalogs: [SemanticPublicationCatalogEvidence]
  var deltas: [SemanticPublicationDeltaEvidence]
  var chain: SemanticPublicationChainEvidence
  var mutations: [SemanticPublicationMutationEvidence]
}

private struct SemanticPublicationCatalogArtifact {
  var label: String
  var directory: URL
  var catalogURL: URL
  var gzipURL: URL
  var manifestURL: URL
  var manifest: CatalogManifest
  var digests: CatalogContentDigests
  var uncompressedBytes: Int64
  var compressedBytes: Int64
  var generationKind: String
  var generationMilliseconds: Double?
}

private struct SemanticPublicationEvidenceHarness {
  private static let outputMarkerData = Data(
    "Grimora Job B semantic publication evidence v1\n".utf8
  )

  let configuration: SemanticPublicationEvidenceConfiguration
  private let fileManager = FileManager.default

  func run() throws {
    try validateSafeDirectoryPaths()
    let sourceCatalog = configuration.baseDirectory.appendingPathComponent("catalog.sqlite")
    let sourceGzip = configuration.baseDirectory.appendingPathComponent("catalog.sqlite.gz")
    let sourceManifestURL = configuration.baseDirectory.appendingPathComponent("manifest.json")
    guard fileManager.fileExists(atPath: sourceCatalog.path),
      fileManager.fileExists(atPath: sourceGzip.path),
      fileManager.fileExists(atPath: sourceManifestURL.path)
    else {
      throw SemanticPublicationEvidenceError.invalidInput(
        "The base directory must contain catalog.sqlite, catalog.sqlite.gz, and manifest.json"
      )
    }
    try rejectSymbolicLinks(at: sourceCatalog, label: "base catalog")
    try rejectSymbolicLinks(at: sourceGzip, label: "base gzip")
    try rejectSymbolicLinks(at: sourceManifestURL, label: "base manifest")

    let baseManifest = try CatalogManifest.decoder().decode(
      CatalogManifest.self,
      from: Data(contentsOf: sourceManifestURL)
    )
    let sourceCounts = try CardDatabase.validateCatalog(
      at: sourceCatalog,
      expectedManifest: baseManifest
    )
    guard let sourceSemanticCounts = sourceCounts.semantic,
      sourceSemanticCounts.tags > 0,
      sourceSemanticCounts.cardTags > 0
    else {
      throw SemanticPublicationEvidenceError.invalidInput(
        "The base build must contain populated semantic tables"
      )
    }
    let sourceDigests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(sourceCatalog))
    )
    guard let manifestDigests = baseManifest.contentDigests,
      manifestDigests == sourceDigests
    else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "The base manifest must contain content digests matching catalog.sqlite"
      )
    }
    guard try fileSize(sourceCatalog) == baseManifest.artifact.uncompressedBytes,
      try fileSize(sourceGzip) == baseManifest.artifact.compressedBytes,
      try FileSHA256.hash(url: sourceCatalog) == baseManifest.artifact.uncompressedSHA256,
      try FileSHA256.hash(url: sourceGzip) == baseManifest.artifact.sha256
    else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "The base catalog artifacts do not match manifest sizes and hashes"
      )
    }
    try validateBaseGzipExpansion(
      sourceCatalog: sourceCatalog,
      sourceGzip: sourceGzip,
      manifest: baseManifest
    )

    try prepareOutputDirectory()
    let artifactA = try stageBaseArtifact(
      sourceCatalog: sourceCatalog,
      sourceGzip: sourceGzip,
      sourceManifestURL: sourceManifestURL,
      manifest: baseManifest,
      digests: sourceDigests
    )
    let (snapshotA, idfCardCount) = try readSemanticInputs(from: artifactA)
    let mutations = try SemanticPublicationMutationChain.make(
      from: snapshotA,
      idfCardCount: idfCardCount
    )
    let artifactB = try stageMutatedArtifact(
      label: "B",
      baseCatalog: artifactA.catalogURL,
      snapshot: mutations.b,
      manifestTemplate: baseManifest,
      version: baseManifest.version + "-job-b-evidence-b-v1"
    )
    let artifactC = try stageMutatedArtifact(
      label: "C",
      baseCatalog: artifactB.catalogURL,
      snapshot: mutations.c,
      manifestTemplate: baseManifest,
      version: baseManifest.version + "-job-b-evidence-c-v1"
    )

    let deltaAB = try buildAndVerifyDelta(from: artifactA, to: artifactB, name: "A-to-B")
    let deltaBC = try buildAndVerifyDelta(from: artifactB, to: artifactC, name: "B-to-C")
    let chain = try verifyChain(
      base: artifactA,
      middle: artifactB,
      firstDelta: configuration.outputDirectory
        .appendingPathComponent("deltas/A-to-B.sqlite"),
      secondDelta: configuration.outputDirectory
        .appendingPathComponent("deltas/B-to-C.sqlite"),
      target: artifactC
    )

    let report = SemanticPublicationEvidenceReport(
      schemaVersion: 1,
      sourceBuildVersion: baseManifest.version,
      provenance: "A is the supplied real semantic build. B and C are deterministic controlled copies; no historical source downloads are fabricated.",
      catalogs: try [artifactA, artifactB, artifactC].map(catalogEvidence),
      deltas: [deltaAB, deltaBC],
      chain: chain,
      mutations: [
        SemanticPublicationMutationEvidence(
          transition: "A-to-B",
          operations: [
            "add semantic tag, alias, membership, and hierarchy edge",
            "rename/update existing tag \(mutations.renamedTagID)",
            "change membership weight for \(mutations.weightedMembershipCardKey.rawValue)",
            "recompute deterministic direct/effective counts and IDF",
          ]
        ),
        SemanticPublicationMutationEvidence(
          transition: "B-to-C",
          operations: [
            "delete controlled tag \(SemanticPublicationMutationChain.addedTagID) and its relationships",
            "follow-up update existing tag \(mutations.renamedTagID)",
            "recompute deterministic direct/effective counts and IDF",
          ]
        ),
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(report).write(
      to: configuration.outputDirectory.appendingPathComponent("report.json"),
      options: .atomic
    )
    print(
      "Semantic publication evidence written to \(configuration.outputDirectory.path)/report.json"
    )
  }

  private func validateSafeDirectoryPaths() throws {
    try rejectSymbolicLinks(at: configuration.baseDirectory, label: "base directory")
    try rejectSymbolicLinks(at: configuration.outputDirectory, label: "output directory")

    let resolvedRoot = configuration.repositoryRoot.resolvingSymlinksInPath().standardizedFileURL
    let resolvedBase = configuration.baseDirectory.resolvingSymlinksInPath().standardizedFileURL
    let resolvedOutput = configuration.outputDirectory.resolvingSymlinksInPath().standardizedFileURL
    guard isStrictDescendant(resolvedOutput, of: resolvedRoot) else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR must resolve inside the repository"
      )
    }
    guard !pathsOverlap(resolvedBase, resolvedOutput) else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "Base and output directories must not overlap after resolving paths"
      )
    }
  }

  private func rejectSymbolicLinks(at url: URL, label: String) throws {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    for component in url.standardizedFileURL.pathComponents.dropFirst() {
      current = current.appendingPathComponent(component)
      guard fileManager.fileExists(atPath: current.path) else { break }
      let attributes = try fileManager.attributesOfItem(atPath: current.path)
      if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
        throw SemanticPublicationEvidenceError.invalidConfiguration(
          "The \(label) must not be or contain a symbolic-link path component"
        )
      }
    }
  }

  private func isStrictDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
    candidate != ancestor && candidate.path.hasPrefix(ancestor.path + "/")
  }

  private func pathsOverlap(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs == rhs || isStrictDescendant(lhs, of: rhs) || isStrictDescendant(rhs, of: lhs)
  }

  private func prepareOutputDirectory() throws {
    try fileManager.createDirectory(
      at: configuration.outputDirectory,
      withIntermediateDirectories: true
    )
    let marker = configuration.outputDirectory
      .appendingPathComponent(".grimora-semantic-publication-evidence")
    let existingEntries = try fileManager.contentsOfDirectory(
      at: configuration.outputDirectory,
      includingPropertiesForKeys: nil
    )
    if !existingEntries.isEmpty {
      try validateExistingOutputMarker(marker)
    }

    try validateSafeDirectoryPaths()
    for component in ["A", "B", "C", "deltas", ".verification"] {
      let url = configuration.outputDirectory.appendingPathComponent(component)
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
    }
    let report = configuration.outputDirectory.appendingPathComponent("report.json")
    if fileManager.fileExists(atPath: report.path) {
      try fileManager.removeItem(at: report)
    }
    try Self.outputMarkerData.write(to: marker, options: .atomic)
    try fileManager.createDirectory(
      at: configuration.outputDirectory.appendingPathComponent("deltas"),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: configuration.outputDirectory.appendingPathComponent(".verification"),
      withIntermediateDirectories: true
    )
  }

  private func validateExistingOutputMarker(_ marker: URL) throws {
    let attributes = try? fileManager.attributesOfItem(atPath: marker.path)
    guard attributes?[.type] as? FileAttributeType == .typeRegular,
      let contents = try? Data(contentsOf: marker),
      contents == Self.outputMarkerData
    else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "The semantic publication output directory must be empty or contain its exact regular-file evidence marker"
      )
    }
  }

  private func validateBaseGzipExpansion(
    sourceCatalog: URL,
    sourceGzip: URL,
    manifest: CatalogManifest
  ) throws {
    let validationParent = configuration.repositoryRoot
      .appendingPathComponent(".hermes/artifacts", isDirectory: true)
    try rejectSymbolicLinks(at: validationParent, label: "base gzip validation directory")
    let resolvedRoot = configuration.repositoryRoot.resolvingSymlinksInPath().standardizedFileURL
    let resolvedValidationParent = validationParent.resolvingSymlinksInPath().standardizedFileURL
    guard isStrictDescendant(resolvedValidationParent, of: resolvedRoot) else {
      throw SemanticPublicationEvidenceError.invalidConfiguration(
        "The base gzip validation directory must resolve inside the repository"
      )
    }

    let validationDirectory = validationParent.appendingPathComponent(
      ".semantic-publication-base-validation-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: validationDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: validationDirectory) }
    let expandedCatalog = validationDirectory.appendingPathComponent("catalog.sqlite")
    do {
      try GzipArchive.decompressFile(at: sourceGzip, to: expandedCatalog)
    } catch {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "The base catalog gzip could not be decompressed for validation: \(error)"
      )
    }

    let sourceSize = try fileSize(sourceCatalog)
    let expandedSize = try fileSize(expandedCatalog)
    let sourceHash = try FileSHA256.hash(url: sourceCatalog)
    let expandedHash = try FileSHA256.hash(url: expandedCatalog)
    guard expandedSize == sourceSize,
      expandedSize == manifest.artifact.uncompressedBytes,
      expandedHash == sourceHash,
      expandedHash == manifest.artifact.uncompressedSHA256
    else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "The expanded base catalog gzip does not match catalog.sqlite and its manifest hash"
      )
    }
  }

  private func stageBaseArtifact(
    sourceCatalog: URL,
    sourceGzip: URL,
    sourceManifestURL: URL,
    manifest: CatalogManifest,
    digests: CatalogContentDigests
  ) throws -> SemanticPublicationCatalogArtifact {
    let directory = configuration.outputDirectory.appendingPathComponent("A", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let gzipURL = directory.appendingPathComponent("catalog.sqlite.gz")
    let manifestURL = directory.appendingPathComponent("manifest.json")
    try fileManager.copyItem(at: sourceCatalog, to: catalogURL)
    try fileManager.copyItem(at: sourceGzip, to: gzipURL)
    try fileManager.copyItem(at: sourceManifestURL, to: manifestURL)
    guard try fileSize(catalogURL) == manifest.artifact.uncompressedBytes,
      try fileSize(gzipURL) == manifest.artifact.compressedBytes,
      try FileSHA256.hash(url: catalogURL) == manifest.artifact.uncompressedSHA256,
      try FileSHA256.hash(url: gzipURL) == manifest.artifact.sha256
    else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "The base catalog artifacts do not match manifest sizes and hashes"
      )
    }
    return SemanticPublicationCatalogArtifact(
      label: "A",
      directory: directory,
      catalogURL: catalogURL,
      gzipURL: gzipURL,
      manifestURL: manifestURL,
      manifest: manifest,
      digests: digests,
      uncompressedBytes: try fileSize(catalogURL),
      compressedBytes: try fileSize(gzipURL),
      generationKind: "real-engine-build",
      generationMilliseconds: configuration.baseBuildWallSeconds.map {
        roundedMilliseconds($0 * 1_000)
      }
    )
  }

  private func readSemanticInputs(
    from artifact: SemanticPublicationCatalogArtifact
  ) throws -> (SemanticCatalogSnapshot, Int) {
    let userURL = configuration.outputDirectory
      .appendingPathComponent(".verification/read-input-user.sqlite")
    defer { removeSQLiteFiles(at: userURL) }
    let database = try CardDatabase(userDatabaseURL: userURL, catalogURL: artifact.catalogURL)
    let snapshot = try database.semanticCatalogSnapshot()
    return (snapshot, Set(snapshot.cardTags.map(\.cardKey)).count)
  }

  private func stageMutatedArtifact(
    label: String,
    baseCatalog: URL,
    snapshot: SemanticCatalogSnapshot,
    manifestTemplate: CatalogManifest,
    version: String
  ) throws -> SemanticPublicationCatalogArtifact {
    let generationStart = ContinuousClock.now
    let directory = configuration.outputDirectory.appendingPathComponent(label, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let gzipURL = directory.appendingPathComponent("catalog.sqlite.gz")
    let manifestURL = directory.appendingPathComponent("manifest.json")
    try fileManager.copyItem(at: baseCatalog, to: catalogURL)
    do {
      let database = try CardDatabase(storage: .file(catalogURL))
      try database.replaceSemanticCatalog(with: snapshot)
      try database.prepareForCatalogDistribution()
    }
    do {
      let database = try SQLiteDatabase(storage: .file(catalogURL))
      try database.execute("VACUUM")
    }

    let counts = try CardDatabase.validateCatalog(at: catalogURL)
    guard counts.semantic != nil else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Controlled catalog \(label) lost semantic tables"
      )
    }
    let digests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(catalogURL))
    )
    try GzipArchive.compressFile(at: catalogURL, to: gzipURL)
    let uncompressedBytes = try fileSize(catalogURL)
    let compressedBytes = try fileSize(gzipURL)
    var manifest = manifestTemplate
    manifest.version = version
    manifest.counts = counts
    manifest.contentDigests = digests
    manifest.artifact = CatalogArtifact(
      downloadURL: URL(string: "https://evidence.invalid/\(label)/catalog.sqlite.gz")!,
      compressedBytes: compressedBytes,
      uncompressedBytes: uncompressedBytes,
      sha256: try FileSHA256.hash(url: gzipURL),
      uncompressedSHA256: try FileSHA256.hash(url: catalogURL)
    )
    try CatalogManifest.encoder(prettyPrinted: true).encode(manifest)
      .write(to: manifestURL, options: .atomic)
    _ = try CardDatabase.validateCatalog(at: catalogURL, expectedManifest: manifest)

    return SemanticPublicationCatalogArtifact(
      label: label,
      directory: directory,
      catalogURL: catalogURL,
      gzipURL: gzipURL,
      manifestURL: manifestURL,
      manifest: manifest,
      digests: digests,
      uncompressedBytes: uncompressedBytes,
      compressedBytes: compressedBytes,
      generationKind: "controlled-copy-generation",
      generationMilliseconds: roundedMilliseconds(milliseconds(since: generationStart))
    )
  }

  private func buildAndVerifyDelta(
    from base: SemanticPublicationCatalogArtifact,
    to target: SemanticPublicationCatalogArtifact,
    name: String
  ) throws -> SemanticPublicationDeltaEvidence {
    let deltaURL = configuration.outputDirectory
      .appendingPathComponent("deltas/\(name).sqlite")
    let gzipURL = URL(fileURLWithPath: deltaURL.path + ".gz")
    let (stats, buildMilliseconds) = try measured {
      try CatalogDeltaBuilder().buildDelta(
        baseCatalogURL: base.catalogURL,
        targetCatalogURL: target.catalogURL,
        baseVersion: base.manifest.version,
        targetVersion: target.manifest.version,
        into: deltaURL
      )
    }
    guard stats.semanticCatalogReplaced else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Delta \(name) did not contain a semantic replacement"
      )
    }
    try GzipArchive.compressFile(at: deltaURL, to: gzipURL)

    let workingURL = configuration.outputDirectory
      .appendingPathComponent(".verification/\(name)-applied.sqlite")
    try fileManager.copyItem(at: base.catalogURL, to: workingURL)
    let (_, applyMilliseconds) = try measured {
      try CatalogDeltaApplier().apply(deltaURL: deltaURL, toWorkingCatalog: workingURL)
    }
    let appliedDigests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(workingURL))
    )
    guard appliedDigests == target.digests else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Applied delta \(name) did not reproduce the target content digests"
      )
    }
    _ = try CardDatabase.validateCatalog(at: workingURL, expectedManifest: target.manifest)
    removeSQLiteFiles(at: workingURL)

    let uncompressedBytes = try fileSize(deltaURL)
    let compressedBytes = try fileSize(gzipURL)
    let targetCompressed = max(target.compressedBytes, 1)
    return SemanticPublicationDeltaEvidence(
      fromVersion: base.manifest.version,
      toVersion: target.manifest.version,
      sqliteSHA256: try FileSHA256.hash(url: deltaURL),
      gzipSHA256: try FileSHA256.hash(url: gzipURL),
      uncompressedBytes: uncompressedBytes,
      compressedBytes: compressedBytes,
      uncompressedPercentOfTargetFullCompressed: roundedPercent(
        uncompressedBytes,
        of: targetCompressed
      ),
      compressedPercentOfTargetFullCompressed: roundedPercent(
        compressedBytes,
        of: targetCompressed
      ),
      buildMilliseconds: roundedMilliseconds(buildMilliseconds),
      applyMilliseconds: roundedMilliseconds(applyMilliseconds),
      stats: SemanticPublicationDeltaStatsEvidence(stats),
      appliedDigestMatched: true,
      appliedManifestValidated: true
    )
  }

  private func verifyChain(
    base: SemanticPublicationCatalogArtifact,
    middle: SemanticPublicationCatalogArtifact,
    firstDelta: URL,
    secondDelta: URL,
    target: SemanticPublicationCatalogArtifact
  ) throws -> SemanticPublicationChainEvidence {
    let workingURL = configuration.outputDirectory
      .appendingPathComponent(".verification/A-to-C-applied.sqlite")
    try fileManager.copyItem(at: base.catalogURL, to: workingURL)
    let (_, milliseconds) = try measured {
      try CatalogDeltaApplier().apply(deltaURL: firstDelta, toWorkingCatalog: workingURL)
      try CatalogDeltaApplier().apply(deltaURL: secondDelta, toWorkingCatalog: workingURL)
    }
    let digests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(workingURL))
    )
    guard digests == target.digests else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "The A-to-B-to-C chain did not reproduce C content digests"
      )
    }
    _ = try CardDatabase.validateCatalog(at: workingURL, expectedManifest: target.manifest)
    removeSQLiteFiles(at: workingURL)
    return SemanticPublicationChainEvidence(
      path: [base.manifest.version, middle.manifest.version, target.manifest.version],
      applyMilliseconds: roundedMilliseconds(milliseconds),
      finalDigestMatched: true,
      finalManifestValidated: true
    )
  }

  private func catalogEvidence(
    _ artifact: SemanticPublicationCatalogArtifact
  ) throws -> SemanticPublicationCatalogEvidence {
    let database = try SQLiteDatabase(storage: .readOnlyFile(artifact.catalogURL))
    let (digests, digestMilliseconds) = try measured {
      try CatalogContentDigest.compute(database)
    }
    guard digests == artifact.digests else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Catalog \(artifact.label) changed while collecting evidence"
      )
    }
    let counts = try CardDatabase.validateCatalog(
      at: artifact.catalogURL,
      expectedManifest: artifact.manifest
    )
    guard let semanticCounts = counts.semantic else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Catalog \(artifact.label) has no semantic counts"
      )
    }
    let integrity = try integrityCheck(database)
    let duplicates = try duplicateCounts(database)
    let orphans = try orphanCounts(database)
    guard integrity == "ok", duplicates.total == 0, orphans.total == 0 else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Catalog \(artifact.label) failed integrity, duplicate, or orphan evidence checks"
      )
    }
    return SemanticPublicationCatalogEvidence(
      label: artifact.label,
      version: artifact.manifest.version,
      generationKind: artifact.generationKind,
      generationMilliseconds: artifact.generationMilliseconds,
      logicalDigests: digests,
      sqliteSHA256: try FileSHA256.hash(url: artifact.catalogURL),
      gzipSHA256: try FileSHA256.hash(url: artifact.gzipURL),
      uncompressedBytes: artifact.uncompressedBytes,
      compressedBytes: artifact.compressedBytes,
      semanticCounts: semanticCounts,
      integrityCheck: integrity,
      duplicates: duplicates,
      orphans: orphans,
      manifestValidated: true,
      measurements: try relationshipMeasurements(
        artifact: artifact,
        digestMilliseconds: digestMilliseconds
      )
    )
  }

  private func relationshipMeasurements(
    artifact: SemanticPublicationCatalogArtifact,
    digestMilliseconds: Double
  ) throws -> SemanticPublicationMeasurements {
    let snapshotDatabaseURL = configuration.outputDirectory
      .appendingPathComponent(".verification/measure-\(artifact.label)-user.sqlite")
    defer { removeSQLiteFiles(at: snapshotDatabaseURL) }
    let cardDatabase = try CardDatabase(
      userDatabaseURL: snapshotDatabaseURL,
      catalogURL: artifact.catalogURL
    )
    let snapshot = try cardDatabase.semanticCatalogSnapshot()
    guard let membership = snapshot.cardTags.sorted(by: {
      ($0.cardKey.rawValue, $0.tagID, $0.source)
        < ($1.cardKey.rawValue, $1.tagID, $1.source)
    }).first else {
      throw SemanticPublicationEvidenceError.verificationFailed(
        "Catalog \(artifact.label) has no representative semantic membership"
      )
    }

    let (tagIDs, cardToTagMilliseconds) = try measured {
      try cardDatabase.semanticTagIDs(for: membership.cardKey)
    }
    let (cardKeys, tagToCardMilliseconds) = try measured {
      try cardDatabase.semanticCardKeys(tagID: membership.tagID)
    }
    let raw = try SQLiteDatabase(storage: .readOnlyFile(artifact.catalogURL))
    let (ancestorCount, ancestorMilliseconds) = try measured {
      try recursiveRelationshipCount(
        raw,
        tagID: membership.tagID,
        direction: .ancestors
      )
    }
    let (descendantCount, descendantMilliseconds) = try measured {
      try recursiveRelationshipCount(
        raw,
        tagID: membership.tagID,
        direction: .descendants
      )
    }
    return SemanticPublicationMeasurements(
      cardToTag: SemanticPublicationMeasurement(
        identifier: membership.cardKey.rawValue,
        resultCount: tagIDs.count,
        milliseconds: roundedMilliseconds(cardToTagMilliseconds)
      ),
      tagToCard: SemanticPublicationMeasurement(
        identifier: membership.tagID,
        resultCount: cardKeys.count,
        milliseconds: roundedMilliseconds(tagToCardMilliseconds)
      ),
      ancestors: SemanticPublicationMeasurement(
        identifier: membership.tagID,
        resultCount: ancestorCount,
        milliseconds: roundedMilliseconds(ancestorMilliseconds)
      ),
      descendants: SemanticPublicationMeasurement(
        identifier: membership.tagID,
        resultCount: descendantCount,
        milliseconds: roundedMilliseconds(descendantMilliseconds)
      ),
      digestMilliseconds: roundedMilliseconds(digestMilliseconds)
    )
  }

  private enum RelationshipDirection {
    case ancestors
    case descendants
  }

  private func recursiveRelationshipCount(
    _ database: SQLiteDatabase,
    tagID: String,
    direction: RelationshipDirection
  ) throws -> Int {
    let recursiveJoin: String
    switch direction {
    case .ancestors:
      recursiveJoin =
        "SELECT edges.parent_tag_id FROM semantic_tag_edges edges JOIN related ON edges.child_tag_id = related.tag_id"
    case .descendants:
      recursiveJoin =
        "SELECT edges.child_tag_id FROM semantic_tag_edges edges JOIN related ON edges.parent_tag_id = related.tag_id"
    }
    let statement = try database.prepare(
      """
      WITH RECURSIVE related(tag_id) AS (
        SELECT ?
        UNION
        \(recursiveJoin)
      )
      SELECT COUNT(*) FROM related
      """
    )
    try statement.bind(tagID, at: 1)
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  private func integrityCheck(_ database: SQLiteDatabase) throws -> String {
    let statement = try database.prepare("PRAGMA integrity_check")
    var results: [String] = []
    while try statement.step() {
      results.append(statement.string(at: 0) ?? "")
    }
    return results.joined(separator: "; ")
  }

  private func duplicateCounts(
    _ database: SQLiteDatabase
  ) throws -> SemanticPublicationDuplicateCounts {
    SemanticPublicationDuplicateCounts(
      tagIDs: try scalarCount(
        database,
        "SELECT COALESCE(SUM(count - 1), 0) FROM (SELECT COUNT(*) count FROM semantic_tags GROUP BY id HAVING count > 1)"
      ),
      sourceSlugs: try scalarCount(
        database,
        "SELECT COALESCE(SUM(count - 1), 0) FROM (SELECT COUNT(*) count FROM semantic_tags GROUP BY source, slug HAVING count > 1)"
      ),
      aliases: try scalarCount(
        database,
        "SELECT COALESCE(SUM(count - 1), 0) FROM (SELECT COUNT(*) count FROM semantic_tag_aliases GROUP BY tag_id, alias_key HAVING count > 1)"
      ),
      edges: try scalarCount(
        database,
        "SELECT COALESCE(SUM(count - 1), 0) FROM (SELECT COUNT(*) count FROM semantic_tag_edges GROUP BY parent_tag_id, child_tag_id HAVING count > 1)"
      ),
      memberships: try scalarCount(
        database,
        "SELECT COALESCE(SUM(count - 1), 0) FROM (SELECT COUNT(*) count FROM semantic_card_tags GROUP BY card_key, tag_id, source HAVING count > 1)"
      ),
      statistics: try scalarCount(
        database,
        "SELECT COALESCE(SUM(count - 1), 0) FROM (SELECT COUNT(*) count FROM semantic_tag_stats GROUP BY tag_id HAVING count > 1)"
      )
    )
  }

  private func orphanCounts(
    _ database: SQLiteDatabase
  ) throws -> SemanticPublicationOrphanCounts {
    SemanticPublicationOrphanCounts(
      aliases: try scalarCount(
        database,
        "SELECT COUNT(*) FROM semantic_tag_aliases a LEFT JOIN semantic_tags t ON t.id = a.tag_id WHERE t.id IS NULL"
      ),
      edgeParents: try scalarCount(
        database,
        "SELECT COUNT(*) FROM semantic_tag_edges e LEFT JOIN semantic_tags t ON t.id = e.parent_tag_id WHERE t.id IS NULL"
      ),
      edgeChildren: try scalarCount(
        database,
        "SELECT COUNT(*) FROM semantic_tag_edges e LEFT JOIN semantic_tags t ON t.id = e.child_tag_id WHERE t.id IS NULL"
      ),
      membershipTags: try scalarCount(
        database,
        "SELECT COUNT(*) FROM semantic_card_tags m LEFT JOIN semantic_tags t ON t.id = m.tag_id WHERE t.id IS NULL"
      ),
      membershipCards: try scalarCount(
        database,
        """
        SELECT COUNT(*) FROM semantic_card_tags m
        WHERE (substr(m.card_key, 1, 2) = 'o:' AND NOT EXISTS (
          SELECT 1 FROM cards WHERE oracle_id = substr(m.card_key, 3)
        )) OR (substr(m.card_key, 1, 2) = 'p:' AND NOT EXISTS (
          SELECT 1 FROM cards WHERE id = substr(m.card_key, 3)
        ))
        """
      ),
      statistics: try scalarCount(
        database,
        "SELECT COUNT(*) FROM semantic_tag_stats s LEFT JOIN semantic_tags t ON t.id = s.tag_id WHERE t.id IS NULL"
      )
    )
  }

  private func scalarCount(_ database: SQLiteDatabase, _ sql: String) throws -> Int {
    let statement = try database.prepare(sql)
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  private func removeSQLiteFiles(at url: URL) {
    for candidate in [
      url,
      URL(fileURLWithPath: url.path + "-wal"),
      URL(fileURLWithPath: url.path + "-shm"),
    ] {
      try? fileManager.removeItem(at: candidate)
    }
  }

  private func measured<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let value = try operation()
    return (value, milliseconds(since: start))
  }

  private func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    let milliseconds = Double(duration.components.seconds) * 1_000
      + Double(duration.components.attoseconds) / 1e15
    return milliseconds
  }

  private func roundedMilliseconds(_ value: Double) -> Double {
    (value * 1_000).rounded() / 1_000
  }

  private func roundedPercent(_ numerator: Int64, of denominator: Int64) -> Double {
    (Double(numerator) / Double(denominator) * 100_000).rounded() / 1_000
  }
}

struct SemanticPublicationEvidenceTests {
  @Test
  func semanticPublicationEvidenceFromRealBaseBuild() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    guard let configuration = try SemanticPublicationEvidenceConfiguration.from(
      environment: ProcessInfo.processInfo.environment,
      repositoryRoot: repositoryRoot
    ) else {
      return
    }

    try SemanticPublicationEvidenceHarness(configuration: configuration).run()
  }

  @Test
  func configurationSkipsWithoutDedicatedEnableEvenWhenPathVariablesAreInherited() throws {
    let repositoryRoot = URL(fileURLWithPath: "/repo", isDirectory: true)

    #expect(
      try SemanticPublicationEvidenceConfiguration.from(
        environment: [:],
        repositoryRoot: repositoryRoot
      ) == nil
    )
    #expect(
      try SemanticPublicationEvidenceConfiguration.from(
        environment: [
          "GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR": "/private/base",
          "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR": "/repo/evidence",
          "GRIMORA_SEMANTIC_PUBLICATION_BASE_BUILD_SECONDS": "invalid",
        ],
        repositoryRoot: repositoryRoot
      ) == nil
    )
  }

  @Test
  func configurationFailsClosedWhenExplicitlyEnabledWithoutNonemptyPaths() throws {
    let repositoryRoot = URL(fileURLWithPath: "/repo", isDirectory: true)

    for environment in [
      ["GRIMORA_SEMANTIC_PUBLICATION_ENABLED": "1"],
      [
        "GRIMORA_SEMANTIC_PUBLICATION_ENABLED": "1",
        "GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR": "   \n",
        "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR": "\t",
      ],
      [
        "GRIMORA_SEMANTIC_PUBLICATION_ENABLED": "1",
        "GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR": "   \n",
        "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR": "/repo/evidence",
      ],
      [
        "GRIMORA_SEMANTIC_PUBLICATION_ENABLED": "1",
        "GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR": "/private/base",
        "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR": "\t",
      ],
      [
        "GRIMORA_SEMANTIC_PUBLICATION_ENABLED": "0",
        "GRIMORA_SEMANTIC_PUBLICATION_BASE_DIR": "/private/base",
        "GRIMORA_SEMANTIC_PUBLICATION_OUTPUT_DIR": "/repo/evidence",
      ],
    ] {
      do {
        _ = try SemanticPublicationEvidenceConfiguration.from(
          environment: environment,
          repositoryRoot: repositoryRoot
        )
        Issue.record("Expected invalidConfiguration for explicitly enabled invalid input")
      } catch SemanticPublicationEvidenceError.invalidConfiguration {
        // Expected.
      } catch {
        Issue.record("Expected invalidConfiguration, got \(error)")
      }
    }
  }

  @Test
  func deterministicFixtureExercisesEvidenceHarnessEndToEnd() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationHarnessTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let network = StubNetworkClient(responses: try EngineFixtures.responses())
    let engine = try GrimoraDataEngine(environment: environment, network: network)
    let baseBuild = try await engine.build(force: true)
    let output = root.appendingPathComponent("evidence", isDirectory: true)

    try SemanticPublicationEvidenceHarness(
      configuration: SemanticPublicationEvidenceConfiguration(
        baseDirectory: baseBuild.directory,
        outputDirectory: output,
        repositoryRoot: repositoryRoot,
        baseBuildWallSeconds: 12.5
      )
    ).run()

    let reportURL = output.appendingPathComponent("report.json")
    #expect(FileManager.default.fileExists(atPath: reportURL.path))
    let reportObject = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: reportURL)) as? [String: Any]
    )
    #expect(reportObject["schemaVersion"] as? Int == 1)
    #expect((reportObject["catalogs"] as? [[String: Any]])?.count == 3)
    let catalogs = try #require(reportObject["catalogs"] as? [[String: Any]])
    #expect(catalogs.first?["generationKind"] as? String == "real-engine-build")
    #expect(catalogs.first?["generationMilliseconds"] as? Double == 12_500)
    #expect(catalogs.dropFirst().allSatisfy { $0["generationMilliseconds"] as? Double != nil })
    #expect((reportObject["deltas"] as? [[String: Any]])?.count == 2)
    #expect(FileManager.default.fileExists(
      atPath: output.appendingPathComponent("deltas/A-to-B.sqlite.gz").path
    ))
    #expect(FileManager.default.fileExists(
      atPath: output.appendingPathComponent("deltas/B-to-C.sqlite.gz").path
    ))
  }

  @Test
  func harnessRejectsSymlinkedOverlappingBaseBeforeDeletingSourceFiles() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationPathSafetyTest-\(UUID().uuidString)",
      isDirectory: true
    )
    let realBase = root.appendingPathComponent("real-base", isDirectory: true)
    let baseLink = root.appendingPathComponent("base-link", isDirectory: true)
    let sourceDirectory = realBase.appendingPathComponent("A", isDirectory: true)
    let sourceSentinel = sourceDirectory.appendingPathComponent("source-sentinel.txt")
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("source must survive\n".utf8).write(to: sourceSentinel)
    try Data("not-a-catalog".utf8).write(
      to: realBase.appendingPathComponent("catalog.sqlite")
    )
    try Data("not-a-gzip".utf8).write(
      to: realBase.appendingPathComponent("catalog.sqlite.gz")
    )
    try Data("not-a-manifest".utf8).write(
      to: realBase.appendingPathComponent("manifest.json")
    )
    try Data("Grimora Job B semantic publication evidence v1\n".utf8).write(
      to: realBase.appendingPathComponent(".grimora-semantic-publication-evidence")
    )
    try FileManager.default.createSymbolicLink(at: baseLink, withDestinationURL: realBase)

    do {
      try SemanticPublicationEvidenceHarness(
        configuration: SemanticPublicationEvidenceConfiguration(
          baseDirectory: baseLink,
          outputDirectory: realBase,
          repositoryRoot: repositoryRoot,
          baseBuildWallSeconds: nil
        )
      ).run()
      Issue.record("Expected symlinked overlapping paths to be rejected")
    } catch SemanticPublicationEvidenceError.invalidConfiguration {
      // Expected.
    } catch {
      Issue.record("Expected invalidConfiguration, got \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: sourceSentinel.path))
    #expect(try Data(contentsOf: sourceSentinel) == Data("source must survive\n".utf8))
  }

  @Test
  func wrongMarkerContentsPreserveExistingOutput() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationWrongMarkerTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let engine = try GrimoraDataEngine(
      environment: environment,
      network: StubNetworkClient(responses: try EngineFixtures.responses())
    )
    let baseBuild = try await engine.build(force: true)
    let output = root.appendingPathComponent("evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("wrong marker\n".utf8).write(
      to: output.appendingPathComponent(".grimora-semantic-publication-evidence")
    )
    let existingReport = output.appendingPathComponent("report.json")
    let existingReportData = Data("existing report must survive\n".utf8)
    try existingReportData.write(to: existingReport)

    do {
      try SemanticPublicationEvidenceHarness(
        configuration: SemanticPublicationEvidenceConfiguration(
          baseDirectory: baseBuild.directory,
          outputDirectory: output,
          repositoryRoot: repositoryRoot,
          baseBuildWallSeconds: nil
        )
      ).run()
      Issue.record("Expected wrong marker contents to be rejected")
    } catch SemanticPublicationEvidenceError.invalidConfiguration {
      // Expected.
    } catch {
      Issue.record("Expected invalidConfiguration, got \(error)")
    }

    #expect(try Data(contentsOf: existingReport) == existingReportData)
  }

  @Test
  func directoryMarkerPreservesExistingOutput() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationDirectoryMarkerTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let engine = try GrimoraDataEngine(
      environment: environment,
      network: StubNetworkClient(responses: try EngineFixtures.responses())
    )
    let baseBuild = try await engine.build(force: true)
    let output = root.appendingPathComponent("evidence", isDirectory: true)
    try FileManager.default.createDirectory(
      at: output.appendingPathComponent(".grimora-semantic-publication-evidence"),
      withIntermediateDirectories: true
    )
    let existingReport = output.appendingPathComponent("report.json")
    let existingReportData = Data("existing report must survive\n".utf8)
    try existingReportData.write(to: existingReport)

    do {
      try SemanticPublicationEvidenceHarness(
        configuration: SemanticPublicationEvidenceConfiguration(
          baseDirectory: baseBuild.directory,
          outputDirectory: output,
          repositoryRoot: repositoryRoot,
          baseBuildWallSeconds: nil
        )
      ).run()
      Issue.record("Expected a directory evidence marker to be rejected")
    } catch SemanticPublicationEvidenceError.invalidConfiguration {
      // Expected.
    } catch {
      Issue.record("Expected invalidConfiguration, got \(error)")
    }

    #expect(try Data(contentsOf: existingReport) == existingReportData)
  }

  @Test
  func symlinkMarkerPreservesExistingOutput() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationSymlinkMarkerTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let engine = try GrimoraDataEngine(
      environment: environment,
      network: StubNetworkClient(responses: try EngineFixtures.responses())
    )
    let baseBuild = try await engine.build(force: true)
    let markerTarget = root.appendingPathComponent("marker-target")
    try Data("Grimora Job B semantic publication evidence v1\n".utf8).write(to: markerTarget)
    let output = root.appendingPathComponent("evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: output.appendingPathComponent(".grimora-semantic-publication-evidence"),
      withDestinationURL: markerTarget
    )
    let existingReport = output.appendingPathComponent("report.json")
    let existingReportData = Data("existing report must survive\n".utf8)
    try existingReportData.write(to: existingReport)

    do {
      try SemanticPublicationEvidenceHarness(
        configuration: SemanticPublicationEvidenceConfiguration(
          baseDirectory: baseBuild.directory,
          outputDirectory: output,
          repositoryRoot: repositoryRoot,
          baseBuildWallSeconds: nil
        )
      ).run()
      Issue.record("Expected a symlink evidence marker to be rejected")
    } catch SemanticPublicationEvidenceError.invalidConfiguration {
      // Expected.
    } catch {
      Issue.record("Expected invalidConfiguration, got \(error)")
    }

    #expect(try Data(contentsOf: existingReport) == existingReportData)
  }

  @Test
  func mismatchedBaseGzipExpansionPreservesExistingOutput() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationGzipValidationTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let engine = try GrimoraDataEngine(
      environment: environment,
      network: StubNetworkClient(responses: try EngineFixtures.responses())
    )
    let baseBuild = try await engine.build(force: true)
    let sourceCatalog = baseBuild.directory.appendingPathComponent("catalog.sqlite")
    let sourceGzip = baseBuild.directory.appendingPathComponent("catalog.sqlite.gz")
    let alteredCatalog = root.appendingPathComponent("altered-catalog.sqlite")
    var alteredData = try Data(contentsOf: sourceCatalog)
    alteredData.append(Data("gzip expansion must not match\n".utf8))
    try alteredData.write(to: alteredCatalog)
    try GzipArchive.compressFile(at: alteredCatalog, to: sourceGzip)

    let manifestURL = baseBuild.directory.appendingPathComponent("manifest.json")
    var manifest = try CatalogManifest.decoder().decode(
      CatalogManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let gzipAttributes = try FileManager.default.attributesOfItem(atPath: sourceGzip.path)
    manifest.artifact.compressedBytes = try #require(
      (gzipAttributes[.size] as? NSNumber)?.int64Value
    )
    manifest.artifact.sha256 = try FileSHA256.hash(url: sourceGzip)
    try CatalogManifest.encoder(prettyPrinted: true).encode(manifest)
      .write(to: manifestURL, options: .atomic)

    let output = root.appendingPathComponent("evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("Grimora Job B semantic publication evidence v1\n".utf8).write(
      to: output.appendingPathComponent(".grimora-semantic-publication-evidence")
    )
    let existingReport = output.appendingPathComponent("report.json")
    let existingReportData = Data("existing report must survive\n".utf8)
    try existingReportData.write(to: existingReport)

    do {
      try SemanticPublicationEvidenceHarness(
        configuration: SemanticPublicationEvidenceConfiguration(
          baseDirectory: baseBuild.directory,
          outputDirectory: output,
          repositoryRoot: repositoryRoot,
          baseBuildWallSeconds: nil
        )
      ).run()
      Issue.record("Expected gzip expansion mismatching catalog.sqlite to be rejected")
    } catch SemanticPublicationEvidenceError.verificationFailed {
      // Expected.
    } catch {
      Issue.record("Expected verificationFailed, got \(error)")
    }

    #expect(try Data(contentsOf: existingReport) == existingReportData)
  }

  @Test
  func missingBaseContentDigestsPreservesExistingOutput() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let root = repositoryRoot.appendingPathComponent(
      ".hermes/artifacts/SemanticPublicationMissingDigestsTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let engine = try GrimoraDataEngine(
      environment: environment,
      network: StubNetworkClient(responses: try EngineFixtures.responses())
    )
    let baseBuild = try await engine.build(force: true)
    let manifestURL = baseBuild.directory.appendingPathComponent("manifest.json")
    var manifest = try CatalogManifest.decoder().decode(
      CatalogManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    manifest.contentDigests = nil
    try CatalogManifest.encoder(prettyPrinted: true).encode(manifest)
      .write(to: manifestURL, options: .atomic)

    let output = root.appendingPathComponent("evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("Grimora Job B semantic publication evidence v1\n".utf8).write(
      to: output.appendingPathComponent(".grimora-semantic-publication-evidence")
    )
    let existingReport = output.appendingPathComponent("report.json")
    let existingReportData = Data("existing report must survive\n".utf8)
    try existingReportData.write(to: existingReport)

    do {
      try SemanticPublicationEvidenceHarness(
        configuration: SemanticPublicationEvidenceConfiguration(
          baseDirectory: baseBuild.directory,
          outputDirectory: output,
          repositoryRoot: repositoryRoot,
          baseBuildWallSeconds: nil
        )
      ).run()
      Issue.record("Expected a base manifest without content digests to be rejected")
    } catch SemanticPublicationEvidenceError.verificationFailed {
      // Expected.
    } catch {
      Issue.record("Expected verificationFailed, got \(error)")
    }

    #expect(try Data(contentsOf: existingReport) == existingReportData)
  }

  @Test
  func controlledMutationChainCoversRequiredChangesAndRecomputesStatistics() throws {
    let rootID = "tag-root"
    let leafID = "tag-leaf"
    let firstCard = SemanticCardKey(rawValue: "o:card-a")
    let secondCard = SemanticCardKey(rawValue: "o:card-b")
    let snapshotA = SemanticCatalogSnapshot(
      tags: [
        SemanticTagRecord(
          id: rootID,
          namespace: "oracle",
          slug: "root",
          label: "Root",
          description: nil,
          similarityEnabled: true,
          source: "fixture"
        ),
        SemanticTagRecord(
          id: leafID,
          namespace: "oracle",
          slug: "leaf",
          label: "Leaf",
          description: nil,
          similarityEnabled: true,
          source: "fixture"
        ),
      ],
      aliases: [],
      edges: [SemanticTagEdgeRecord(parentTagID: rootID, childTagID: leafID)],
      cardTags: [
        SemanticCardTagRecord(
          cardKey: firstCard,
          tagID: leafID,
          weightMillis: 500,
          annotation: nil,
          source: "fixture"
        ),
        SemanticCardTagRecord(
          cardKey: secondCard,
          tagID: rootID,
          weightMillis: 600,
          annotation: nil,
          source: "fixture"
        ),
      ],
      stats: []
    )
    let chain = try SemanticPublicationMutationChain.make(from: snapshotA, idfCardCount: 2)

    #expect(chain.b.tags.contains { $0.id == SemanticPublicationMutationChain.addedTagID })
    #expect(chain.b.tags.first { $0.id == leafID }?.label != "Leaf")
    #expect(chain.b.cardTags.first { $0.tagID == leafID }?.weightMillis != 500)
    #expect(
      chain.b.edges.contains {
        $0.parentTagID == leafID && $0.childTagID == SemanticPublicationMutationChain.addedTagID
      }
    )
    #expect(!chain.c.tags.contains { $0.id == SemanticPublicationMutationChain.addedTagID })
    #expect(chain.b.stats.first { $0.tagID == rootID }?.effectiveCardCount == 2)
    #expect(chain.c.stats.first { $0.tagID == rootID }?.effectiveCardCount == 2)
    #expect(chain.b.stats.first { $0.tagID == rootID }?.inverseFrequencyMillis == 1_000)
    #expect(chain.c.stats.first { $0.tagID == rootID }?.inverseFrequencyMillis == 1_000)
    #expect(chain.b.stats.count == chain.b.tags.count)
    #expect(chain.c.stats.count == chain.c.tags.count)
  }
}
