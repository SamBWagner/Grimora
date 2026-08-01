import Foundation

public enum ScryfallCardStreamScannerError: Error, Equatable, Sendable {
  case unrecognizedStream
  case unterminatedObject
}

/// Streams the top-level card objects out of a Scryfall bulk artifact without holding the whole
/// file in memory. Handles both shapes Scryfall has served: a single top-level JSON array, and the
/// current JSON Lines stream (one card object per line).
public enum ScryfallCardStreamScanner {
  public static func scan(
    url: URL,
    progress: (@Sendable (Int64) async -> Void)? = nil,
    body: (Data) throws -> Void
  ) async throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var started = false
    var collecting = false
    var objectDepth = 0
    var isInsideString = false
    var isEscaping = false
    var object = Data()
    var scannedBytes: Int64 = 0
    var lastProgress: Int64 = 0

    while true {
      let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
      if chunk.isEmpty {
        break
      }
      scannedBytes += Int64(chunk.count)
      for byte in chunk {
        if !started {
          if byte.isJSONWhitespace {
            continue
          }
          switch byte {
          case UInt8(ascii: "["):
            // Legacy shape: every card object sits inside one top-level array.
            started = true
            continue
          case UInt8(ascii: "{"):
            // JSON Lines: this byte already opens the first card, so fall through and collect it.
            started = true
          default:
            throw ScryfallCardStreamScannerError.unrecognizedStream
          }
        }

        if collecting {
          object.append(byte)
          if isInsideString {
            if isEscaping {
              isEscaping = false
            } else if byte == UInt8(ascii: "\\") {
              isEscaping = true
            } else if byte == UInt8(ascii: "\"") {
              isInsideString = false
            }
            continue
          }
          if byte == UInt8(ascii: "\"") {
            isInsideString = true
          } else if byte == UInt8(ascii: "{") {
            objectDepth += 1
          } else if byte == UInt8(ascii: "}") {
            objectDepth -= 1
            if objectDepth == 0 {
              try body(object)
              object.removeAll(keepingCapacity: true)
              collecting = false
            }
          }
          continue
        }

        if byte == UInt8(ascii: "{") {
          collecting = true
          objectDepth = 1
          isInsideString = false
          isEscaping = false
          object.append(byte)
        }
      }

      if scannedBytes - lastProgress >= 4 * 1024 * 1024 {
        lastProgress = scannedBytes
        await progress?(scannedBytes)
      }
    }

    guard started else {
      throw ScryfallCardStreamScannerError.unrecognizedStream
    }
    guard !collecting else {
      throw ScryfallCardStreamScannerError.unterminatedObject
    }
    await progress?(scannedBytes)
  }
}

private extension UInt8 {
  var isJSONWhitespace: Bool {
    self == UInt8(ascii: " ")
      || self == UInt8(ascii: "\n")
      || self == UInt8(ascii: "\r")
      || self == UInt8(ascii: "\t")
  }
}
