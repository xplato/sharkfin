import Foundation
import GRDB

nonisolated struct IndexedFile: Codable, Identifiable, Sendable {
  var id: Int64?
  var path: String
  var directoryId: Int64
  var filename: String
  var fileExtension: String?
  var sizeBytes: Int64
  var modifiedAt: Date
  var contentHash: String
  var mimeType: String?
  var width: Int?
  var height: Int?
  var indexedAt: Date
  var thumbnailPath: String?

  enum CodingKeys: String, CodingKey {
    case id, path, directoryId, filename
    case fileExtension
    case sizeBytes, modifiedAt, contentHash, mimeType
    case width, height, indexedAt, thumbnailPath
  }
}

nonisolated extension IndexedFile: FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "files"
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
