import Foundation
import GRDB
import Testing

@testable import Sharkfin

struct DatabaseModelTests {
  
  /// Creates a fresh in-memory database with foreign keys enabled.
  private func makeDatabase() throws -> AppDatabase {
    var config = Configuration()
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
    return try AppDatabase(DatabaseQueue(configuration: config))
  }
  
  /// Inserts a directory and returns the database + directory ID.
  private func makeDatabaseWithDirectory(
    path: String = "/test",
    enabled: Bool = true
  ) throws -> (AppDatabase, Int64) {
    let db = try makeDatabase()
    var dir = SharkfinDirectory(
      path: path,
      label: nil,
      enabled: enabled,
      addedAt: Date(),
      lastIndexedAt: nil,
      bookmark: nil
    )
    try db.addDirectory(&dir)
    return (db, dir.id!)
  }
  
  // MARK: - Migration
  
  @Test func migrationCreatesAllTables() throws {
    let db = try makeDatabase()
    let tables = try db.dbQueue.read { dbConn in
      try String.fetchAll(
        dbConn,
        sql:
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'grdb%' ORDER BY name"
      )
    }
    #expect(tables.contains("directories"))
    #expect(tables.contains("files"))
    #expect(tables.contains("fileEmbeddings"))
  }
  
  // MARK: - SharkfinDirectory
  
  @Test func insertAndFetchDirectory() throws {
    let db = try makeDatabase()
    var dir = SharkfinDirectory(
      path: "/Users/test/Photos",
      label: "Photos",
      enabled: true,
      addedAt: Date(),
      lastIndexedAt: nil,
      bookmark: nil
    )
    try db.addDirectory(&dir)
    #expect(dir.id != nil)
    
    let fetched = try db.dbQueue.read { db in
      try SharkfinDirectory.fetchOne(db, id: dir.id!)
    }
    #expect(fetched?.path == "/Users/test/Photos")
    #expect(fetched?.label == "Photos")
    #expect(fetched?.enabled == true)
  }
  
  @Test func directoryPathIsUnique() throws {
    let db = try makeDatabase()
    var dir1 = SharkfinDirectory(
      path: "/same/path",
      label: nil,
      enabled: true,
      addedAt: Date(),
      lastIndexedAt: nil,
      bookmark: nil
    )
    try db.addDirectory(&dir1)
    
    var dir2 = SharkfinDirectory(
      path: "/same/path",
      label: nil,
      enabled: true,
      addedAt: Date(),
      lastIndexedAt: nil,
      bookmark: nil
    )
    #expect(throws: (any Error).self) {
      try db.addDirectory(&dir2)
    }
  }
  
  @Test func updateDirectoryEnabled() throws {
    let (db, dirId) = try makeDatabaseWithDirectory()
    try db.updateDirectoryEnabled(id: dirId, enabled: false)
    
    let fetched = try db.dbQueue.read { dbConn in
      try SharkfinDirectory.fetchOne(dbConn, id: dirId)
    }
    #expect(fetched?.enabled == false)
  }
  
  @Test func deleteDirectoryCascadesToFiles() throws {
    let (db, dirId) = try makeDatabaseWithDirectory()
    
    try db.dbQueue.write { dbConn in
      var file = IndexedFile(
        path: "/test/photo.jpg",
        directoryId: dirId,
        filename: "photo.jpg",
        fileExtension: "jpg",
        sizeBytes: 1024,
        modifiedAt: Date(),
        contentHash: "abc123",
        mimeType: nil,
        width: 100,
        height: 100,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try file.insert(dbConn)
    }
    
    try db.deleteDirectory(id: dirId)
    
    let fileCount = try db.dbQueue.read { dbConn in
      try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM files")
    }
    #expect(fileCount == 0)
  }
  
  // MARK: - IndexedFile
  
  @Test func filePathIsUnique() throws {
    let (db, dirId) = try makeDatabaseWithDirectory()
    
    try db.dbQueue.write { dbConn in
      var f1 = IndexedFile(
        path: "/test/dup.jpg",
        directoryId: dirId,
        filename: "dup.jpg",
        fileExtension: "jpg",
        sizeBytes: 100,
        modifiedAt: Date(),
        contentHash: "a",
        mimeType: nil,
        width: nil,
        height: nil,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try f1.insert(dbConn)
    }
    
    #expect(throws: (any Error).self) {
      try db.dbQueue.write { dbConn in
        var f2 = IndexedFile(
          path: "/test/dup.jpg",
          directoryId: dirId,
          filename: "dup.jpg",
          fileExtension: "jpg",
          sizeBytes: 200,
          modifiedAt: Date(),
          contentHash: "b",
          mimeType: nil,
          width: nil,
          height: nil,
          indexedAt: Date(),
          thumbnailPath: nil
        )
        try f2.insert(dbConn)
      }
    }
  }
  
  // MARK: - FileEmbedding
  
  @Test func insertAndFetchEmbedding() throws {
    let (db, dirId) = try makeDatabaseWithDirectory()
    
    var file = IndexedFile(
      path: "/test/a.jpg",
      directoryId: dirId,
      filename: "a.jpg",
      fileExtension: "jpg",
      sizeBytes: 100,
      modifiedAt: Date(),
      contentHash: "x",
      mimeType: nil,
      width: nil,
      height: nil,
      indexedAt: Date(),
      thumbnailPath: nil
    )
    try db.dbQueue.write { dbConn in try file.insert(dbConn) }
    
    let fakeEmbedding = [Float](repeating: 0.1, count: 512)
    let embData = fakeEmbedding.withUnsafeBufferPointer { Data(buffer: $0) }
    let embedding = FileEmbedding(fileId: file.id!, embedding: embData, modelId: CLIPModelPackage.default.id)
    try db.dbQueue.write { dbConn in try embedding.insert(dbConn) }
    
    let fetched = try db.dbQueue.read { dbConn in
      try FileEmbedding.fetchOne(dbConn, id: file.id!)
    }
    #expect(fetched != nil)
    #expect(fetched?.embedding.count == 512 * MemoryLayout<Float>.size)
  }
  
  @Test func embeddingCascadesOnFileDelete() throws {
    let (db, dirId) = try makeDatabaseWithDirectory()
    
    var file = IndexedFile(
      path: "/test/b.jpg",
      directoryId: dirId,
      filename: "b.jpg",
      fileExtension: "jpg",
      sizeBytes: 100,
      modifiedAt: Date(),
      contentHash: "y",
      mimeType: nil,
      width: nil,
      height: nil,
      indexedAt: Date(),
      thumbnailPath: nil
    )
    try db.dbQueue.write { dbConn in try file.insert(dbConn) }
    
    let embData = [Float](repeating: 0, count: 512)
      .withUnsafeBufferPointer { Data(buffer: $0) }
    try db.dbQueue.write { dbConn in
      try FileEmbedding(fileId: file.id!, embedding: embData, modelId: CLIPModelPackage.default.id).insert(dbConn)
    }
    
    try db.dbQueue.write { dbConn in
      _ = try IndexedFile.deleteOne(dbConn, id: file.id!)
    }
    
    let count = try db.dbQueue.read { dbConn in
      try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM fileEmbeddings")
    }
    #expect(count == 0)
  }
  
  // MARK: - AppDatabase queries
  
  @Test func fetchAvailableFileTypesOnlyFromEnabledDirectories() async throws {
    let db = try makeDatabase()
    
    var enabledDir = SharkfinDirectory(
      path: "/enabled",
      label: nil,
      enabled: true,
      addedAt: Date(),
      lastIndexedAt: nil,
      bookmark: nil
    )
    try db.addDirectory(&enabledDir)
    
    var disabledDir = SharkfinDirectory(
      path: "/disabled",
      label: nil,
      enabled: false,
      addedAt: Date(),
      lastIndexedAt: nil,
      bookmark: nil
    )
    try db.addDirectory(&disabledDir)
    
    let enabledDirId = enabledDir.id!
    let disabledDirId = disabledDir.id!
    
    try await db.dbQueue.write { dbConn in
      var f1 = IndexedFile(
        path: "/enabled/a.jpg",
        directoryId: enabledDirId,
        filename: "a.jpg",
        fileExtension: "jpg",
        sizeBytes: 100,
        modifiedAt: Date(),
        contentHash: "a",
        mimeType: nil,
        width: nil,
        height: nil,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try f1.insert(dbConn)
      
      var f2 = IndexedFile(
        path: "/disabled/b.png",
        directoryId: disabledDirId,
        filename: "b.png",
        fileExtension: "png",
        sizeBytes: 100,
        modifiedAt: Date(),
        contentHash: "b",
        mimeType: nil,
        width: nil,
        height: nil,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try f2.insert(dbConn)
    }
    
    let types = try await db.fetchAvailableFileTypes()
    #expect(types.contains("jpg"))
    #expect(!types.contains("png"))
  }
  
  @Test func fetchStatsCountsCorrectly() throws {
    let db = try makeDatabase()
    
    var dir = SharkfinDirectory(
      path: "/test",
      label: nil,
      enabled: true,
      addedAt: Date(),
      lastIndexedAt: Date(),
      bookmark: nil
    )
    try db.addDirectory(&dir)
    
    try db.dbQueue.write { dbConn in
      var file = IndexedFile(
        path: "/test/c.jpg",
        directoryId: dir.id!,
        filename: "c.jpg",
        fileExtension: "jpg",
        sizeBytes: 5000,
        modifiedAt: Date(),
        contentHash: "c",
        mimeType: nil,
        width: nil,
        height: nil,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try file.insert(dbConn)
    }
    
    let stats = try db.fetchStats()
    #expect(stats.totalFiles == 1)
    #expect(stats.totalEnabledFiles == 1)
    #expect(stats.totalDirectories == 1)
    #expect(stats.enabledDirectories == 1)
    #expect(stats.totalSizeBytes == 5000)
    #expect(stats.lastIndexedAt != nil)
  }
}
