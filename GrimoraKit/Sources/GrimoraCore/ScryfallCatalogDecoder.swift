import Foundation

public enum ScryfallCatalogDecoder {
  public static func decodeRecord(
    from data: Data,
    decoder: JSONDecoder = JSONDecoder()
  ) throws -> CardRecord {
    let card = try decoder.decode(ScryfallCardDTO.self, from: data)
    return ScryfallCardNormalizer.normalize(card)
  }
}
