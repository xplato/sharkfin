import GRDB
import Foundation

/// Manages the SQLite database for Sharkfin.
final class AppDatabase: Sendable {
  let dbQueue: DatabaseQueue
  
  init(_ dbQueue: DatabaseQueue) throws {
    self.dbQueue = dbQueue
    try migrator.migrate(dbQueue)
  }
  
  private var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    
#if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
#endif
    
    migrator.registerMigration("v1") { db in
      // directories
      try db.create(table: "directories") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("path", .text).notNull().unique()
        t.column("label", .text)
        t.column("enabled", .boolean).notNull().defaults(to: true)
        t.column("addedAt", .datetime).notNull()
        t.column("lastIndexedAt", .datetime)
        t.column("bookmark", .blob)
      }
      
      // files
      try db.create(table: "files") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("path", .text).notNull().unique()
        t.belongsTo("directory", onDelete: .cascade).notNull()
        t.column("filename", .text).notNull()
        t.column("fileExtension", .text)
        t.column("sizeBytes", .integer).notNull()
        t.column("modifiedAt", .datetime).notNull()
        t.column("contentHash", .text).notNull()
        t.column("mimeType", .text)
        t.column("width", .integer)
        t.column("height", .integer)
        t.column("indexedAt", .datetime).notNull()
        t.column("thumbnailPath", .text)
      }
      
      // file_embeddings
      try db.create(table: "fileEmbeddings") { t in
        t.primaryKey("fileId", .integer)
          .references("files", onDelete: .cascade)
        t.column("embedding", .blob).notNull()
      }
      
      // file_metadata
      try db.create(table: "fileMetadata") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("file", onDelete: .cascade).notNull()
        t.column("key", .text).notNull()
        t.column("value", .text).notNull()
        t.column("source", .text).notNull()
        t.column("createdAt", .datetime).notNull()
        t.uniqueKey(["fileId", "key", "source"])
      }
      
      // index_jobs
      try db.create(table: "indexJobs") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("directory", onDelete: .cascade).notNull()
        t.column("status", .text).notNull().defaults(to: "pending")
        t.column("totalFiles", .integer)
        t.column("processedFiles", .integer).defaults(to: 0)
        t.column("startedAt", .datetime)
        t.column("completedAt", .datetime)
        t.column("error", .text)
      }
      
      // Indexes
      try db.create(indexOn: "files", columns: ["directoryId"])
      try db.create(indexOn: "files", columns: ["contentHash"])
      try db.create(indexOn: "fileMetadata", columns: ["fileId"])
      try db.create(indexOn: "fileMetadata", columns: ["key"])
    }
    
    return migrator
  }
  
  /// The app's data directory in Application Support.
  static let dataDirectoryURL: URL = {
    let appSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    return appSupportURL.appendingPathComponent("com.lgx.sharkfin", isDirectory: true)
  }()

  // MARK: - Shared Instance
  
  static let shared: AppDatabase = {
    do {
      return try makeShared()
    } catch {
      fatalError("Failed to initialize database: \(error)")
    }
  }()
  
  private static func makeShared() throws -> AppDatabase {
    let fileManager = FileManager.default
    let appSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directoryURL = appSupportURL.appendingPathComponent(
      "com.lgx.sharkfin",
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    let dbURL = directoryURL.appendingPathComponent("sharkfin.db")
    
    var config = Configuration()
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode=WAL")
      try db.execute(sql: "PRAGMA foreign_keys=ON")
    }
    
    let dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
    return try AppDatabase(dbQueue)
  }
  
  // MARK: - Directory Operations
  
  func addDirectory(_ directory: inout SharkfinDirectory) throws {
    try dbQueue.write { db in
      try directory.insert(db)
    }
  }
  
  func deleteDirectory(id: Int64) throws {
    try dbQueue.write { db in
      _ = try SharkfinDirectory.deleteOne(db, id: id)
    }
  }
  
  func updateDirectoryEnabled(id: Int64, enabled: Bool) throws {
    try dbQueue.write { db in
      if var directory = try SharkfinDirectory.fetchOne(db, id: id) {
        directory.enabled = enabled
        try directory.update(db)
      }
    }
  }

  // MARK: - Stats

  nonisolated struct Stats: Sendable, Equatable {
    var totalFiles: Int
    var totalEnabledFiles: Int
    var totalEmbeddings: Int
    var totalDirectories: Int
    var enabledDirectories: Int
    var totalSizeBytes: Int64
    var lastIndexedAt: Date?
    var databaseSizeBytes: Int64
    var thumbnailsSizeBytes: Int64
  }

  func fetchStats() throws -> Stats {
    let fm = FileManager.default
    let dbURL = Self.dataDirectoryURL.appendingPathComponent("sharkfin.db")
    let dbSize = (try? fm.attributesOfItem(atPath: dbURL.path)[.size] as? Int64) ?? 0
    // WAL and SHM files also contribute to actual disk usage
    let walSize = (try? fm.attributesOfItem(
      atPath: dbURL.path + "-wal")[.size] as? Int64) ?? 0

    let thumbsDir = ThumbnailGenerator.thumbnailsDirectory
    var thumbnailsSize: Int64 = 0
    if let enumerator = fm.enumerator(at: thumbsDir, includingPropertiesForKeys: [.fileSizeKey]) {
      for case let fileURL as URL in enumerator {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        thumbnailsSize += Int64(size)
      }
    }

    return try dbQueue.read { db in
      let totalFiles = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM files") ?? 0
      let totalEnabledFiles = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM files WHERE directoryId IN (SELECT id FROM directories WHERE enabled = 1)") ?? 0
      let totalEmbeddings = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM fileEmbeddings") ?? 0
      let totalDirectories = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM directories") ?? 0
      let enabledDirectories = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM directories WHERE enabled = 1") ?? 0
      let totalSizeBytes = try Int64.fetchOne(
        db, sql: "SELECT COALESCE(SUM(sizeBytes), 0) FROM files") ?? 0
      let lastIndexedAt = try Date.fetchOne(
        db, sql: "SELECT MAX(lastIndexedAt) FROM directories")

      return Stats(
        totalFiles: totalFiles,
        totalEnabledFiles: totalEnabledFiles,
        totalEmbeddings: totalEmbeddings,
        totalDirectories: totalDirectories,
        enabledDirectories: enabledDirectories,
        totalSizeBytes: totalSizeBytes,
        lastIndexedAt: lastIndexedAt,
        databaseSizeBytes: dbSize + walSize,
        thumbnailsSizeBytes: thumbnailsSize
      )
    }
  }

  /// Returns the security-scoped bookmark for the directory containing a file.
  func directoryBookmark(forFileId fileId: Int64) async throws -> Data? {
    try await dbQueue.read { db in
      try Data.fetchOne(db, sql: """
        SELECT d.bookmark FROM directories d
        JOIN files f ON f.directoryId = d.id
        WHERE f.id = ?
        """, arguments: [fileId])
    }
  }

}
