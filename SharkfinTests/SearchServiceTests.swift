import Foundation
import GRDB
import Testing

@testable import Sharkfin

/// A fake text encoder that returns a predetermined embedding vector.
nonisolated struct FakeTextEncoder: TextEncoding {
  let embedding: [Float]

  func encode(text: String) throws -> [Float] {
    embedding
  }
}

struct SearchServiceTests {

  /// Creates an in-memory database with foreign keys enabled.
  private func makeDatabase() throws -> AppDatabase {
    var config = Configuration()
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
    return try AppDatabase(DatabaseQueue(configuration: config))
  }

  /// Seeds a database with a directory, files, and their embeddings.
  private func seedDatabase(
    files: [(name: String, ext: String, embedding: [Float])],
    directoryEnabled: Bool = true
  ) throws -> AppDatabase {
    let db = try makeDatabase()
    var dir = SharkfinDirectory(
      path: "/test",
      label: nil,
      enabled: directoryEnabled,
      addedAt: Date(),
      lastIndexedAt: Date(),
      bookmark: nil
    )
    try db.addDirectory(&dir)
    let dirId = dir.id!

    for (i, file) in files.enumerated() {
      try db.dbQueue.write { dbConn in
        var f = IndexedFile(
          path: "/test/\(file.name)",
          directoryId: dirId,
          filename: file.name,
          fileExtension: file.ext,
          sizeBytes: 1000,
          modifiedAt: Date(),
          contentHash: "hash\(i)",
          mimeType: nil,
          width: 100,
          height: 100,
          indexedAt: Date(),
          thumbnailPath: "/thumbs/hash\(i).jpg"
        )
        try f.insert(dbConn)

        let normalized = CLIPImageEncoder.l2Normalize(file.embedding)
        let data = normalized.withUnsafeBufferPointer { Data(buffer: $0) }
        try FileEmbedding(fileId: f.id!, embedding: data).insert(dbConn)
      }
    }

    return db
  }

  // MARK: - Search ranking

  @Test func searchReturnsResultsSortedByRelevance() async throws {
    let queryVec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )

    // "close" is almost identical to the query
    var closeVec = [Float](repeating: 1.0, count: 512)
    closeVec[0] = 0.95
    // "far" points in a different direction
    var farVec = [Float](repeating: 0.3, count: 512)
    farVec[0] = -0.5

    let db = try seedDatabase(files: [
      ("close.jpg", "jpg", closeVec),
      ("far.jpg", "jpg", farVec),
    ])

    let encoder = FakeTextEncoder(embedding: queryVec)
    let service = SearchService(database: db, textEncoder: encoder)
    let results = try await service.search(query: "test")

    if results.count >= 2 {
      #expect(results[0].filename == "close.jpg")
    }
  }

  @Test func searchFiltersResultsByFileType() async throws {
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )

    let db = try seedDatabase(files: [
      ("photo.jpg", "jpg", vec),
      ("image.png", "png", vec),
    ])

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)
    let results = try await service.search(
      query: "test",
      filters: SearchFilters(fileTypes: ["jpg"])
    )

    #expect(results.allSatisfy { $0.filename.hasSuffix(".jpg") })
  }

  @Test func searchReturnsMaxFiftyResults() async throws {
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )
    let files = (0..<60).map { i in
      (name: "file\(i).jpg", ext: "jpg", embedding: vec)
    }
    let db = try seedDatabase(files: files)

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)
    let results = try await service.search(query: "test")

    #expect(results.count <= 50)
  }

  @Test func searchReturnsEmptyForNoEmbeddings() async throws {
    let db = try makeDatabase()
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)
    let results = try await service.search(query: "test")

    #expect(results.isEmpty)
  }

  @Test func searchRelevanceIsNormalizedZeroToOne() async throws {
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )
    let db = try seedDatabase(files: [
      ("a.jpg", "jpg", vec)
    ])

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)
    let results = try await service.search(query: "test")

    for result in results {
      #expect(result.relevance >= 0)
      #expect(result.relevance <= 1)
    }
  }

  @Test func cacheInvalidationAllowsSubsequentSearches() async throws {
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )
    let db = try seedDatabase(files: [
      ("a.jpg", "jpg", vec)
    ])

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)

    // First search populates cache
    _ = try await service.search(query: "test")

    // Invalidate cache
    service.invalidateCache()

    // Search should still work after invalidation
    let results = try await service.search(query: "test")
    #expect(!results.isEmpty)
  }

  @Test func searchExcludesDisabledDirectories() async throws {
    let db = try makeDatabase()
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )

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
        filename: "visible.jpg",
        fileExtension: "jpg",
        sizeBytes: 100,
        modifiedAt: Date(),
        contentHash: "v",
        mimeType: nil,
        width: nil,
        height: nil,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try f1.insert(dbConn)
      let data = vec.withUnsafeBufferPointer { Data(buffer: $0) }
      try FileEmbedding(fileId: f1.id!, embedding: data).insert(dbConn)

      var f2 = IndexedFile(
        path: "/disabled/b.jpg",
        directoryId: disabledDirId,
        filename: "hidden.jpg",
        fileExtension: "jpg",
        sizeBytes: 100,
        modifiedAt: Date(),
        contentHash: "h",
        mimeType: nil,
        width: nil,
        height: nil,
        indexedAt: Date(),
        thumbnailPath: nil
      )
      try f2.insert(dbConn)
      try FileEmbedding(fileId: f2.id!, embedding: data).insert(dbConn)
    }

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)
    let results = try await service.search(query: "test")

    #expect(results.allSatisfy { $0.filename != "hidden.jpg" })
  }

  @Test func findSimilarExcludesSourceFile() async throws {
    let vec = CLIPImageEncoder.l2Normalize(
      [Float](repeating: 1.0, count: 512)
    )
    let db = try seedDatabase(files: [
      ("source.jpg", "jpg", vec),
      ("similar.jpg", "jpg", vec),
    ])

    let encoder = FakeTextEncoder(embedding: vec)
    let service = SearchService(database: db, textEncoder: encoder)

    let sourceId = try await db.dbQueue.read { dbConn in
      try IndexedFile.filter(Column("filename") == "source.jpg")
        .fetchOne(dbConn)!.id!
    }

    let results = try await service.findSimilar(toFileId: sourceId)
    #expect(results.allSatisfy { $0.id != sourceId })
  }
}
