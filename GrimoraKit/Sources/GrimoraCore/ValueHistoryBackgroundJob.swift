import Foundation

public enum ValueHistoryBackgroundStage: String, Codable, Equatable, Sendable {
  case pending
  case downloadingPrices
  case decompressingPrices
  case mappingCards
  case importingHistory
  case committingHistory
  case completed
  case failed
}

public enum ValueHistoryBackgroundStatus: String, Codable, Equatable, Sendable {
  case pending
  case running
  case succeeded
  case failed
}

public struct ValueHistoryBackgroundJob: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var mtgjsonDate: String
  public var mtgjsonVersion: String
  public var cardDatabaseIdentity: String
  public var stage: ValueHistoryBackgroundStage
  public var status: ValueHistoryBackgroundStatus
  public var downloadedBytes: Int64
  public var totalDownloadBytes: Int64?
  public var scannedBytes: Int64
  public var totalScanBytes: Int64?
  public var importedPricePoints: Int
  public var createdAt: String
  public var updatedAt: String
  public var completedAt: String?
  public var lastError: String?

  public init(
    id: String = UUID().uuidString,
    mtgjsonDate: String,
    mtgjsonVersion: String,
    cardDatabaseIdentity: String,
    stage: ValueHistoryBackgroundStage = .pending,
    status: ValueHistoryBackgroundStatus = .pending,
    downloadedBytes: Int64 = 0,
    totalDownloadBytes: Int64? = nil,
    scannedBytes: Int64 = 0,
    totalScanBytes: Int64? = nil,
    importedPricePoints: Int = 0,
    createdAt: String,
    updatedAt: String,
    completedAt: String? = nil,
    lastError: String? = nil
  ) {
    self.id = id
    self.mtgjsonDate = mtgjsonDate
    self.mtgjsonVersion = mtgjsonVersion
    self.cardDatabaseIdentity = cardDatabaseIdentity
    self.stage = stage
    self.status = status
    self.downloadedBytes = downloadedBytes
    self.totalDownloadBytes = totalDownloadBytes
    self.scannedBytes = scannedBytes
    self.totalScanBytes = totalScanBytes
    self.importedPricePoints = importedPricePoints
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.completedAt = completedAt
    self.lastError = lastError
  }

  public var meta: MTGJSONPriceHistoryMeta {
    MTGJSONPriceHistoryMeta(date: mtgjsonDate, version: mtgjsonVersion)
  }
}
