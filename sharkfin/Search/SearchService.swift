import Foundation
import GRDB

/// Encodes text queries with CLIP and ranks stored embeddings by cosine similarity.
final class SearchService: @unchecked Sendable {
  
  private let database: AppDatabase
  private let textEncoder: CLIPTextEncoder
  
  private nonisolated static let minRawScore: Float = 0.16
  private nonisolated static let scoreFloor: Float = 0.18
  private nonisolated static let scoreCeiling: Float = 0.35
  
  init(database: AppDatabase, textEncoder: CLIPTextEncoder) {
    self.database = database
    self.textEncoder = textEncoder
  }
  
  nonisolated func search(query: String) async throws -> [SearchResult] {
    // 1. Encode query text on background thread
    let queryEmbedding = try textEncoder.encode(text: query)
    print("[Search] Query embedding: \(queryEmbedding.count) dims, norm=\(sqrt(queryEmbedding.reduce(0) { $0 + $1 * $1 }))")
    
    // 2. Load all embeddings + file info from DB
    let rows: [EmbeddingRow] = try await database.dbQueue.read { db in
      try EmbeddingRow.fetchAll(db, sql: """
                SELECT e.fileId, e.embedding, f.filename, f.path, f.thumbnailPath
                FROM fileEmbeddings e
                JOIN files f ON f.id = e.fileId
                JOIN directories d ON d.id = f.directoryId
                WHERE d.enabled = 1
                """)
    }
    print("[Search] Loaded \(rows.count) embeddings from DB")
    
    // 3. Compute cosine similarity (dot product for L2-normalized vectors)
    var results: [SearchResult] = []
    var maxScore: Float = -1
    var dimMismatchCount = 0
    
    for row in rows {
      let fileEmbedding: [Float] = row.embedding.withUnsafeBytes { buffer in
        Array(buffer.bindMemory(to: Float.self))
      }
      
      guard fileEmbedding.count == queryEmbedding.count else {
        dimMismatchCount += 1
        continue
      }
      
      var rawScore: Float = 0
      for i in 0..<queryEmbedding.count {
        rawScore += queryEmbedding[i] * fileEmbedding[i]
      }
      
      if rawScore > maxScore { maxScore = rawScore }
      
      guard rawScore >= Self.minRawScore else { continue }
      
      let relevance = max(0, min(1, (rawScore - Self.scoreFloor) / (Self.scoreCeiling - Self.scoreFloor)))
      
      results.append(SearchResult(
        id: row.fileId,
        filename: row.filename,
        path: row.path,
        thumbnailPath: row.thumbnailPath,
        rawScore: rawScore,
        relevance: relevance
      ))
    }
    
    print("[Search] Results: \(results.count)/\(rows.count), maxScore=\(maxScore), dimMismatch=\(dimMismatchCount)")
    results.sort { $0.relevance > $1.relevance }
    return Array(results.prefix(50))
  }
  /// Find files visually similar to a given file using embedding cosine similarity.
  nonisolated func findSimilar(toFileId fileId: Int64, limit: Int = 4) async throws -> [SearchResult] {
    // Load the target file's embedding
    let targetRow: EmbeddingRow? = try await database.dbQueue.read { db in
      try EmbeddingRow.fetchOne(db, sql: """
        SELECT e.fileId, e.embedding, f.filename, f.path, f.thumbnailPath
        FROM fileEmbeddings e
        JOIN files f ON f.id = e.fileId
        JOIN directories d ON d.id = f.directoryId
        WHERE e.fileId = ? AND d.enabled = 1
        """, arguments: [fileId])
    }
    
    guard let target = targetRow else { return [] }
    
    let targetEmbedding: [Float] = target.embedding.withUnsafeBytes { buffer in
      Array(buffer.bindMemory(to: Float.self))
    }
    
    // Load all other embeddings
    let rows: [EmbeddingRow] = try await database.dbQueue.read { db in
      try EmbeddingRow.fetchAll(db, sql: """
        SELECT e.fileId, e.embedding, f.filename, f.path, f.thumbnailPath
        FROM fileEmbeddings e
        JOIN files f ON f.id = e.fileId
        JOIN directories d ON d.id = f.directoryId
        WHERE e.fileId != ? AND d.enabled = 1
        """, arguments: [fileId])
    }
    
    // Compute similarity and find top N
    var scored: [(SearchResult, Float)] = []
    for row in rows {
      let embedding: [Float] = row.embedding.withUnsafeBytes { buffer in
        Array(buffer.bindMemory(to: Float.self))
      }
      guard embedding.count == targetEmbedding.count else { continue }
      
      var score: Float = 0
      for i in 0..<targetEmbedding.count {
        score += targetEmbedding[i] * embedding[i]
      }
      
      scored.append((SearchResult(
        id: row.fileId,
        filename: row.filename,
        path: row.path,
        thumbnailPath: row.thumbnailPath,
        rawScore: score,
        relevance: score
      ), score))
    }
    
    scored.sort { $0.1 > $1.1 }
    return Array(scored.prefix(limit).map(\.0))
  }
}

// MARK: - Internal row type for the JOIN query

private nonisolated struct EmbeddingRow: FetchableRecord, Decodable, Sendable {
  var fileId: Int64
  var embedding: Data
  var filename: String
  var path: String
  var thumbnailPath: String?
}
