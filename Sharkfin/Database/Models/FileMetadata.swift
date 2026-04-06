import GRDB
import Foundation

nonisolated struct FileMetadata: Codable, Identifiable, Sendable {
  var id: Int64?
  var fileId: Int64
  var key: String
  var value: String
  var source: String
  var createdAt: Date
}

nonisolated extension FileMetadata: FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "fileMetadata"
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
