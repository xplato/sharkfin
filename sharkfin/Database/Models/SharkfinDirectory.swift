import GRDB
import Foundation

nonisolated struct SharkfinDirectory: Codable, Identifiable, Sendable {
  var id: Int64?
  var path: String
  var label: String?
  var enabled: Bool
  var watch: Bool
  var addedAt: Date
  var lastIndexedAt: Date?
  var bookmark: Data?
}

nonisolated extension SharkfinDirectory: FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "directories"
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
