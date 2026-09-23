import Foundation

public struct ScryfallOracleTagDTO: Decodable, Equatable, Sendable {
  public var object: String
  public var id: String
  public var label: String
  public var slug: String
  public var type: String
  public var uri: URL
  public var description: String?
  public var parentIDs: [String]
  public var childIDs: [String]
  public var aliases: [String]
  public var taggings: [ScryfallOracleTaggingDTO]

  public init(
    object: String,
    id: String,
    label: String,
    slug: String,
    type: String,
    uri: URL,
    description: String?,
    parentIDs: [String],
    childIDs: [String],
    aliases: [String],
    taggings: [ScryfallOracleTaggingDTO]
  ) {
    self.object = object
    self.id = id
    self.label = label
    self.slug = slug
    self.type = type
    self.uri = uri
    self.description = description
    self.parentIDs = parentIDs
    self.childIDs = childIDs
    self.aliases = aliases
    self.taggings = taggings
  }

  enum CodingKeys: String, CodingKey {
    case object
    case id
    case label
    case slug
    case type
    case uri
    case description
    case parentIDs = "parent_ids"
    case childIDs = "child_ids"
    case aliases
    case taggings
  }
}

public struct ScryfallOracleTaggingDTO: Decodable, Equatable, Sendable {
  public var oracleID: String
  public var weight: ScryfallOracleTaggingWeight
  public var annotation: String?

  public init(
    oracleID: String,
    weight: ScryfallOracleTaggingWeight,
    annotation: String?
  ) {
    self.oracleID = oracleID
    self.weight = weight
    self.annotation = annotation
  }

  enum CodingKeys: String, CodingKey {
    case oracleID = "oracle_id"
    case weight
    case annotation
  }
}

public enum ScryfallOracleTaggingWeight: String, Decodable, Equatable, Sendable {
  case weak
  case median
  case strong
  case veryStrong = "very_strong"
}
