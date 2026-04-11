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
  private let modelId: String
  
  private nonisolated static let minRawScore: Float = 0.16
  private nonisolated static let scoreFloor: Float = 0.18
  private nonisolated static let scoreCeiling: Float = 0.35
  
  // MARK: - Embedding cache
  
  private let cacheState = OSAllocatedUnfairLock(initialState: CacheSlot())
  private var notificationObserver: (any NSObjectProtocol)?
  
  init(database: AppDatabase, textEncoder: any TextEncoding, modelId: String) {
    self.database = database
    self.textEncoder = textEncoder
    self.modelId = modelId
    
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
    cacheState.withLock { state in
      state.stale = true
    }
    LoggingService.shared.info("Cache invalidated", category: "Search")
  }
  
  nonisolated func search(
    query: String,
    filters: SearchFilters = SearchFilters()
  ) async throws -> [SearchResult] {
    let log = LoggingService.shared
    let profiling = log.isDebugEnabled
    let clock: ContinuousClock? = profiling ? ContinuousClock() : nil
    let totalStart = clock?.now
    
    // 1. Encode query text
    let encodeStart = clock?.now
    let queryEmbedding = try textEncoder.encode(text: query)
    let encodeDuration = encodeStart.map { clock!.now - $0 }
    
    // 2. Get cached embeddings (loads from DB on first call)
    let cacheStart = clock?.now
    let cached = try await getCache()
    let cacheDuration = cacheStart.map { clock!.now - $0 }
    guard cached.count > 0, cached.dims == queryEmbedding.count else {
      return []
    }
    
    // 3. Compute all dot products via matrix × vector multiply
    //    embeddings is (N × dims), query is (dims × 1), result is (N × 1)
    let mmulStart = clock?.now
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
    let mmulDuration = mmulStart.map { clock!.now - $0 }
    
    // 4. Filter by minimum score, apply filters, normalize relevance, collect results
    let filterStart = clock?.now
    let filterByType = !filters.fileTypes.isEmpty
    let scopePrefix = filters.directoryScope.map {
      ($0.hasSuffix("/") ? $0 : $0 + "/")
    }
    var results: [SearchResult] = []
    for i in 0..<cached.count {
      let rawScore = scores[i]
      guard rawScore >= Self.minRawScore else { continue }
      if filterByType {
        guard filters.fileTypes.contains(cached.fileExtensions[i]) else {
          continue
        }
      }
      if let scopePrefix {
        guard cached.paths[i].hasPrefix(scopePrefix) else { continue }
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
    
    if profiling, let totalStart {
      let filterDuration = filterStart.map { clock!.now - $0 }
      let totalDuration = clock!.now - totalStart
      log.debug(
        """
        "\(query)" — \(cached.count) embeddings, \(results.count) results
          Text encode:  \(encodeDuration!)
          Cache load:   \(cacheDuration!)
          vDSP_mmul:    \(mmulDuration!)
          Filter+sort:  \(filterDuration!)
          Total:        \(totalDuration)
        """,
        category: "Search"
      )
    }
    
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
    let task = cacheState.withLock { (state: inout CacheSlot) -> Task<EmbeddingCache, any Error> in
      // If a task exists (loading or completed), always return it —
      // even if stale. We'll check staleness after the load finishes.
      if let existing = state.task {
        return existing
      }
      let newTask = Task { try await loadCache() }
      state.task = newTask
      state.stale = false
      return newTask
    }
    
    let result = try await task.value
    
    // After the load finishes, if we were marked stale during the load,
    // clear the task so the *next* search triggers a fresh reload.
    cacheState.withLock { (state: inout CacheSlot) in
      if state.stale {
        state.task = nil
        state.stale = false
      }
    }
    
    return result
  }
  
  private nonisolated func loadCache() async throws -> EmbeddingCache {
    let activeModelId = modelId
    let sql = """
      SELECT e.fileId, e.embedding, f.filename, f.path, f.thumbnailPath,
             LOWER(f.fileExtension) AS fileExtension
      FROM fileEmbeddings e
      JOIN files f ON f.id = e.fileId
      JOIN directories d ON d.id = f.directoryId
      WHERE d.enabled = 1 AND e.modelId = ?
      """
    
    return try await database.dbQueue.read { db in
      let count = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM fileEmbeddings e
          JOIN files f ON f.id = e.fileId
          JOIN directories d ON d.id = f.directoryId
          WHERE d.enabled = 1 AND e.modelId = ?
          """,
        arguments: [activeModelId]
      ) ?? 0
      
      let cursor = try EmbeddingRow.fetchCursor(
        db,
        sql: sql,
        arguments: [activeModelId]
      )
      
      guard let firstRow = try cursor.next() else {
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
      embeddings.reserveCapacity(count * dims)
      var fileIds = [Int64]()
      fileIds.reserveCapacity(count)
      var filenames = [String]()
      filenames.reserveCapacity(count)
      var paths = [String]()
      paths.reserveCapacity(count)
      var thumbnailPaths = [String?]()
      thumbnailPaths.reserveCapacity(count)
      var fileExtensions = [String]()
      fileExtensions.reserveCapacity(count)
      
      // Process first row
      firstRow.embedding.withUnsafeBytes { buffer in
        embeddings.append(contentsOf: buffer.bindMemory(to: Float.self))
      }
      fileIds.append(firstRow.fileId)
      filenames.append(firstRow.filename)
      paths.append(firstRow.path)
      thumbnailPaths.append(firstRow.thumbnailPath)
      fileExtensions.append(firstRow.fileExtension ?? "")
      
      // Process remaining rows via cursor — only one row's Data is alive at a time
      while let row = try cursor.next() {
        let rowDims = row.embedding.count / MemoryLayout<Float>.size
        guard rowDims == dims else { continue }
        row.embedding.withUnsafeBytes { buffer in
          embeddings.append(contentsOf: buffer.bindMemory(to: Float.self))
        }
        fileIds.append(row.fileId)
        filenames.append(row.filename)
        paths.append(row.path)
        thumbnailPaths.append(row.thumbnailPath)
        fileExtensions.append(row.fileExtension ?? "")
      }
      
      LoggingService.shared.info(
        "Cached \(fileIds.count) embeddings (\(dims) dims, \(embeddings.count * MemoryLayout<Float>.size / 1024)KB) for model \(activeModelId)",
        category: "Search"
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
}

// MARK: - Internal types

private struct CacheSlot: @unchecked Sendable {
  var task: Task<EmbeddingCache, any Error>?
  var stale = false
}

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
