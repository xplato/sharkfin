import Foundation
import GRDB

nonisolated struct FileEmbedding: Codable, Sendable {
  var fileId: Int64
  var embedding: Data
  var modelId: String
}

nonisolated extension FileEmbedding: FetchableRecord, PersistableRecord {
  static let databaseTableName = "fileEmbeddings"
}
