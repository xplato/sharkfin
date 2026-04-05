import GRDB
import Foundation

nonisolated struct FileEmbedding: Codable, Identifiable, Sendable {
  var fileId: Int64
  var embedding: Data
  
  var id: Int64 { fileId }
}

nonisolated extension FileEmbedding: FetchableRecord, PersistableRecord {
  static let databaseTableName = "fileEmbeddings"
}
