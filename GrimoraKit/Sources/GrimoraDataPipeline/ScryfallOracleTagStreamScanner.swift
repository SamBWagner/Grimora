import Foundation

public enum ScryfallOracleTagStreamScanner {
  public static func scan(
    url: URL,
    progress: (@Sendable (Int64) async -> Void)? = nil,
    body: (ScryfallOracleTagDTO) throws -> Void
  ) async throws {
    let decoder = JSONDecoder()
    try await ScryfallCardStreamScanner.scan(url: url, progress: progress) { objectData in
      try body(decoder.decode(ScryfallOracleTagDTO.self, from: objectData))
    }
  }
}
