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
  try await ScryfallJSONArrayScanner.scan(url: url) { objects.append($0) }

  #expect(objects.count == 2)
  #expect(String(decoding: objects[0], as: UTF8.self).contains(#""id":"one""#))
  #expect(String(decoding: objects[1], as: UTF8.self).contains(#""id":"two""#))
}

@Test
func rejectsInterruptedTopLevelObject() async throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("scryfall-interrupted-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  try Data(#"[{"id":"one""#.utf8).write(to: url)

  await #expect(throws: ScryfallJSONArrayScannerError.unterminatedObject) {
    try await ScryfallJSONArrayScanner.scan(url: url) { _ in }
  }
}
