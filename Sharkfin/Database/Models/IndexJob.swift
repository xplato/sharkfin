import Foundation
import GRDB

nonisolated struct IndexJob: Codable, Identifiable, Sendable {
  var id: Int64?
  var directoryId: Int64
  var status: String
  var totalFiles: Int?
  var processedFiles: Int
  var startedAt: Date?
  var completedAt: Date?
  var error: String?
}

nonisolated extension IndexJob: FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "indexJobs"
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
