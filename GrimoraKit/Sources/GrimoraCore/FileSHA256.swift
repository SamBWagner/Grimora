import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#elseif canImport(Crypto)
  import Crypto
#endif

public enum FileSHA256Error: Error, Equatable, Sendable {
  case unavailable
}

public enum FileSHA256 {
  public static func hash(url: URL) throws -> String {
    #if canImport(CryptoKit) || canImport(Crypto)
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      var hasher = SHA256()
      while true {
        let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if data.isEmpty {
          break
        }
        hasher.update(data: data)
      }
      return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    #else
      throw FileSHA256Error.unavailable
    #endif
  }
}
