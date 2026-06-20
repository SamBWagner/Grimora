import Foundation

public enum ScryfallJSONArrayScannerError: Error, Equatable, Sendable {
  case expectedArray
  case unterminatedObject
}

public enum ScryfallJSONArrayScanner {
  public static func scan(
    url: URL,
    progress: (@Sendable (Int64) async -> Void)? = nil,
    body: (Data) throws -> Void
  ) async throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var foundArray = false
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
        if !foundArray {
          if byte.isJSONWhitespace {
            continue
          }
          guard byte == UInt8(ascii: "[") else {
            throw ScryfallJSONArrayScannerError.expectedArray
          }
          foundArray = true
          continue
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

    guard foundArray else {
      throw ScryfallJSONArrayScannerError.expectedArray
    }
    guard !collecting else {
      throw ScryfallJSONArrayScannerError.unterminatedObject
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
