import Foundation
import Testing
@testable import GrimoraDataPipeline

@Test
func streamsTopLevelJSONObjects() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-stream-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data(#"[{"id":"one","nested":{"value":"}"}},{"id":"two"}]"#.utf8).write(to: url)

  var objects: [Data] = []
  try await ScryfallCardStreamScanner.scan(url: url) { objects.append($0) }

  #expect(objects.count == 2)
  #expect(String(decoding: objects[0], as: UTF8.self).contains(#""id":"one""#))
  #expect(String(decoding: objects[1], as: UTF8.self).contains(#""id":"two""#))
}

@Test
func streamsJSONLinesObjects() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-jsonl-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data(
    """
    {"id":"one","nested":{"value":"}"}}
    {"id":"two"}

    """.utf8
  ).write(to: url)

  var objects: [Data] = []
  try await ScryfallCardStreamScanner.scan(url: url) { objects.append($0) }

  #expect(objects.count == 2)
  #expect(String(decoding: objects[0], as: UTF8.self).contains(#""id":"one""#))
  #expect(String(decoding: objects[1], as: UTF8.self).contains(#""id":"two""#))
}

@Test
func rejectsStreamThatIsNeitherArrayNorObject() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-bogus-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data(#""not a card stream""#.utf8).write(to: url)

  await #expect(throws: ScryfallCardStreamScannerError.unrecognizedStream) {
    try await ScryfallCardStreamScanner.scan(url: url) { _ in }
  }
}

@Test
func rejectsInterruptedTopLevelObject() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-interrupted-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data(#"[{"id":"one""#.utf8).write(to: url)

  await #expect(throws: ScryfallCardStreamScannerError.unterminatedObject) {
    try await ScryfallCardStreamScanner.scan(url: url) { _ in }
  }
}

@Test
func rejectsTruncatedTopLevelArrayAfterCompleteObject() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-truncated-array-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data(#"[{"id":"one"}"#.utf8).write(to: url)

  await #expect(throws: ScryfallCardStreamScannerError.unrecognizedStream) {
    try await ScryfallCardStreamScanner.scan(url: url) { _ in }
  }
}

@Test
func rejectsTrailingGarbageAfterJSONLinesObject() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-trailing-garbage-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data("{\"id\":\"one\"}\ngarbage".utf8).write(to: url)

  await #expect(throws: ScryfallCardStreamScannerError.unrecognizedStream) {
    try await ScryfallCardStreamScanner.scan(url: url) { _ in }
  }
}

@Test
func rejectsJSONLinesObjectsSeparatedOnlyByHorizontalWhitespace() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-jsonl-same-line-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data("{\"id\":\"one\"} {\"id\":\"two\"}".utf8).write(to: url)

  await #expect(throws: ScryfallCardStreamScannerError.unrecognizedStream) {
    try await ScryfallCardStreamScanner.scan(url: url) { _ in }
  }
}

@Test
func rejectsJSONLinesObjectSplitAcrossMultipleLines() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-jsonl-multiline-object-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data("{\"id\":\"one\",\n\"nested\":{}}".utf8).write(to: url)

  await #expect(throws: ScryfallCardStreamScannerError.unrecognizedStream) {
    try await ScryfallCardStreamScanner.scan(url: url) { _ in }
  }
}
