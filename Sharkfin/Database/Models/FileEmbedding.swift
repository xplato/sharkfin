import Foundation
import GRDB

nonisolated struct FileEmbedding: Codable, Identifiable, Sendable {
  var fileId: Int64
  var embedding: Data
  var modelId: String
  
  var id: Int64 { fileId }
}

nonisolated extension FileEmbedding: FetchableRecord, PersistableRecord {
  static let databaseTableName = "fileEmbeddings"
}
