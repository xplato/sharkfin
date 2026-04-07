import Accelerate
import Foundation
import GRDB
import os

extension Notification.Name {
  static let searchCacheDidInvalidate = Notification.Name(
    "searchCacheDidInvalidate"
  )
}

/// Encodes text queries with CLIP and ranks stored embeddings by cosine similarity.
///
/// Embeddings are cached in a contiguous float buffer after the first query.
/// Dot products are computed via a single `vDSP_mmul` call (Accelerate).
final class SearchService: @unchecked Sendable {

  private let database: AppDatabase
  private let textEncoder: any TextEncoding

  private nonisolated static let minRawScore: Float = 0.16
  private nonisolated static let scoreFloor: Float = 0.18
  private nonisolated static let scoreCeiling: Float = 0.35

  // MARK: - Embedding cache

  private let cache = OSAllocatedUnfairLock<EmbeddingCache?>(initialState: nil)
  private var notificationObserver: (any NSObjectProtocol)?

  init(database: AppDatabase, textEncoder: any TextEncoding) {
    self.database = database
    self.textEncoder = textEncoder

    notificationObserver = NotificationCenter.default.addObserver(
      forName: .searchCacheDidInvalidate,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.invalidateCache()
    }
  }

  deinit {
    if let notificationObserver {
      NotificationCenter.default.removeObserver(notificationObserver)
    }
  }

  nonisolated func invalidateCache() {
    cache.withLock { $0 = nil }
    print("[Search] Cache invalidated")
  }

  nonisolated func search(
    query: String,
    filters: SearchFilters = SearchFilters()
  ) async throws -> [SearchResult] {
    // 1. Encode query text
    let queryEmbedding = try textEncoder.encode(text: query)

    // 2. Get cached embeddings (loads from DB on first call)
    let cached = try await getCache()
    guard cached.count > 0, cached.dims == queryEmbedding.count else {
      return []
    }

    // 3. Compute all dot products via matrix × vector multiply
    //    embeddings is (N × dims), query is (dims × 1), result is (N × 1)
    var scores = [Float](repeating: 0, count: cached.count)
    cached.embeddings.withUnsafeBufferPointer { embBuf in
      queryEmbedding.withUnsafeBufferPointer { qBuf in
        vDSP_mmul(
          embBuf.baseAddress!,
          1,
          qBuf.baseAddress!,
          1,
          &scores,
          1,
          vDSP_Length(cached.count),
          1,
          vDSP_Length(cached.dims)
        )
      }
    }

    // 4. Filter by minimum score, apply filters, normalize relevance, collect results
    let filterByType = !filters.fileTypes.isEmpty
    var results: [SearchResult] = []
    for i in 0..<cached.count {
      let rawScore = scores[i]
      guard rawScore >= Self.minRawScore else { continue }
      if filterByType {
        guard filters.fileTypes.contains(cached.fileExtensions[i]) else {
          continue
        }
      }
      let relevance = max(
        0,
        min(
          1,
          (rawScore - Self.scoreFloor) / (Self.scoreCeiling - Self.scoreFloor)
        )
      )
      results.append(
        SearchResult(
          id: cached.fileIds[i],
          filename: cached.filenames[i],
          path: cached.paths[i],
          thumbnailPath: cached.thumbnailPaths[i],
          rawScore: rawScore,
          relevance: relevance
        )
      )
    }

    results.sort { $0.relevance > $1.relevance }
    return results
  }

  /// Find files visually similar to a given file using embedding cosine similarity.
  nonisolated func findSimilar(toFileId fileId: Int64, limit: Int = 4)
    async throws -> [SearchResult]
  {
    let cached = try await getCache()
    guard cached.count > 0 else { return [] }

    // Find the target file's embedding in the cache
    guard let targetIndex = cached.fileIds.firstIndex(of: fileId) else {
      return []
    }
    let offset = targetIndex * cached.dims
    let targetEmbedding = Array(
      cached.embeddings[offset..<(offset + cached.dims)]
    )

    // Compute all dot products via matrix × vector multiply
    var scores = [Float](repeating: 0, count: cached.count)
    cached.embeddings.withUnsafeBufferPointer { embBuf in
      targetEmbedding.withUnsafeBufferPointer { qBuf in
        vDSP_mmul(
          embBuf.baseAddress!,
          1,
          qBuf.baseAddress!,
          1,
          &scores,
          1,
          vDSP_Length(cached.count),
          1,
          vDSP_Length(cached.dims)
        )
      }
    }

    // Collect results, excluding the target file itself
    var results: [SearchResult] = []
    for i in 0..<cached.count {
      guard cached.fileIds[i] != fileId else { continue }
      let score = scores[i]
      results.append(
        SearchResult(
          id: cached.fileIds[i],
          filename: cached.filenames[i],
          path: cached.paths[i],
          thumbnailPath: cached.thumbnailPaths[i],
          rawScore: score,
          relevance: score
        )
      )
    }

    results.sort { $0.relevance > $1.relevance }
    return Array(results.prefix(limit))
  }

  // MARK: - Cache management

  private nonisolated func getCache() async throws -> EmbeddingCache {
    if let existing = cache.withLock({ $0 }) {
      return existing
    }

    let loaded = try await loadCache()
    cache.withLock { $0 = loaded }
    return loaded
  }

  private nonisolated func loadCache() async throws -> EmbeddingCache {
    let rows: [EmbeddingRow] = try await database.dbQueue.read { db in
      try EmbeddingRow.fetchAll(
        db,
        sql: """
          SELECT e.fileId, e.embedding, f.filename, f.path, f.thumbnailPath,
                 LOWER(f.fileExtension) AS fileExtension
          FROM fileEmbeddings e
          JOIN files f ON f.id = e.fileId
          JOIN directories d ON d.id = f.directoryId
          WHERE d.enabled = 1
          """
      )
    }

    guard let firstRow = rows.first else {
      return EmbeddingCache(
        embeddings: [],
        fileIds: [],
        filenames: [],
        paths: [],
        thumbnailPaths: [],
        fileExtensions: [],
        count: 0,
        dims: 0
      )
    }

    let dims = firstRow.embedding.count / MemoryLayout<Float>.size
    var embeddings = [Float]()
    embeddings.reserveCapacity(rows.count * dims)
    var fileIds = [Int64]()
    fileIds.reserveCapacity(rows.count)
    var filenames = [String]()
    filenames.reserveCapacity(rows.count)
    var paths = [String]()
    paths.reserveCapacity(rows.count)
    var thumbnailPaths = [String?]()
    thumbnailPaths.reserveCapacity(rows.count)
    var fileExtensions = [String]()
    fileExtensions.reserveCapacity(rows.count)

    for row in rows {
      let floats: [Float] = row.embedding.withUnsafeBytes { buffer in
        Array(buffer.bindMemory(to: Float.self))
      }
      guard floats.count == dims else { continue }
      embeddings.append(contentsOf: floats)
      fileIds.append(row.fileId)
      filenames.append(row.filename)
      paths.append(row.path)
      thumbnailPaths.append(row.thumbnailPath)
      fileExtensions.append(row.fileExtension ?? "")
    }

    print(
      "[Search] Cached \(fileIds.count) embeddings (\(dims) dims, \(embeddings.count * MemoryLayout<Float>.size / 1024)KB)"
    )
    return EmbeddingCache(
      embeddings: embeddings,
      fileIds: fileIds,
      filenames: filenames,
      paths: paths,
      thumbnailPaths: thumbnailPaths,
      fileExtensions: fileExtensions,
      count: fileIds.count,
      dims: dims
    )
  }
}

// MARK: - Internal types

private struct EmbeddingCache: Sendable {
  let embeddings: [Float]  // Contiguous N × dims buffer
  let fileIds: [Int64]
  let filenames: [String]
  let paths: [String]
  let thumbnailPaths: [String?]
  let fileExtensions: [String]
  let count: Int
  let dims: Int
}

private nonisolated struct EmbeddingRow: FetchableRecord, Decodable, Sendable {
  var fileId: Int64
  var embedding: Data
  var filename: String
  var path: String
  var thumbnailPath: String?
  var fileExtension: String?
}
