import Foundation
import Testing
@testable import GrimoraDataPipeline

@Test
func streamsOracleTagsWithHierarchyAliasesWeightsAndAnnotations() async throws {
  let url = try #require(Bundle.module.url(
    forResource: "oracle-tags-sample",
    withExtension: "jsonl",
    subdirectory: "Fixtures"
  ))
  var tags: [ScryfallOracleTagDTO] = []

  try await ScryfallOracleTagStreamScanner.scan(url: url) { tags.append($0) }

  #expect(tags.count == 2)
  let giantTutor = tags[0]
  #expect(giantTutor.object == "tag")
  #expect(giantTutor.id == "00155182-3099-4742-be68-f8b4ea259d78")
  #expect(giantTutor.slug == "tutor-creature-giant")
  #expect(giantTutor.label == "tutor-creature-giant")
  #expect(giantTutor.type == "oracle")
  #expect(giantTutor.uri == URL(string: "https://tagger.scryfall.com/tags/card/tutor-creature-giant"))
  #expect(giantTutor.description == "Cards that tutor Giant cards.")
  #expect(giantTutor.aliases == ["tutor-giant"])
  #expect(giantTutor.parentIDs == ["23fd5e7c-3ddc-49b0-818f-bd5fabb04d8f"])
  #expect(giantTutor.childIDs == ["child-tag-id"])
  #expect(giantTutor.taggings == [
    ScryfallOracleTaggingDTO(
      oracleID: "2445e58b-87ed-4ab2-8209-a5e1f566fba7",
      weight: .median,
      annotation: nil
    ),
    ScryfallOracleTaggingDTO(
      oracleID: "d2c6502d-fefd-4c9f-9d7b-6dfcc43316e1",
      weight: .veryStrong,
      annotation: "Blood Artist"
    ),
  ])

  #expect(tags[1].description == nil)
  #expect(tags[1].taggings.map(\.weight) == [.strong, .weak])
}
