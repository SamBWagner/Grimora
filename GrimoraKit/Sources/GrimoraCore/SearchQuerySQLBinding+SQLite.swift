import Foundation

extension SearchQuery.SQLBinding {
  func apply(to statement: SQLiteStatement, index: Int32) throws {
    switch self {
    case .text(let value):
      try statement.bind(value, at: index)
    case .int(let value):
      try statement.bind(value, at: index)
    case .double(let value):
      try statement.bind(value, at: index)
    }
  }
}
