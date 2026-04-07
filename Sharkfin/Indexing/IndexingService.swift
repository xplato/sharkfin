import AppKit
import Foundation
import GRDB
import Observation

nonisolated enum IndexingPhase: Sendable, Equatable {
  case scanning
  case indexing
  case complete(Int)
  case upToDate
  case error(String)
  case cancelled
}

nonisolated struct IndexingProgress: Sendable, Equatable {
  var phase: IndexingPhase
  var total: Int
  var processed: Int
  var currentFile: String

  init(
    phase: IndexingPhase,
    total: Int = 0,
    processed: Int = 0,
    currentFile: String = ""
  ) {
    self.phase = phase
    self.total = total
    self.processed = processed
    self.currentFile = currentFile
  }
}

@MainActor
@Observable
final class IndexingService {
  private(set) var progressByDirectory: [Int64: IndexingProgress] = [:]

  let database: AppDatabase
  private let modelManager: CLIPModelManager
  private var activeTasks: [Int64: Task<Void, Never>] = [:]

  init(database: AppDatabase, modelManager: CLIPModelManager) {
    self.database = database
    self.modelManager = modelManager
  }

  var modelsReady: Bool {
    modelManager.visionModelURL != nil
  }

  func isIndexing(_ directoryId: Int64) -> Bool {
    activeTasks[directoryId] != nil
  }

  func indexDirectory(_ directory: SharkfinDirectory) {
    guard let dirId = directory.id else { return }
    guard activeTasks[dirId] == nil else { return }
    guard let bookmark = directory.bookmark else { return }

    guard let visionModelURL = modelManager.visionModelURL else {
      progressByDirectory[dirId] = IndexingProgress(
        phase: .error("Vision model not downloaded")
      )
      return
    }

    progressByDirectory[dirId] = IndexingProgress(phase: .scanning)

    let db = database
    activeTasks[dirId] = Task.detached { [weak self] in
      do {
        try await Self.performIndexing(
          dirId: dirId,
          bookmark: bookmark,
          visionModelURL: visionModelURL,
          database: db
        ) { [weak self] progress in
          let service = self
          Task { @MainActor in
            service?.progressByDirectory[dirId] = progress
          }
        }
      } catch is CancellationError {
        let service = self
        await MainActor.run {
          service?.progressByDirectory[dirId] = IndexingProgress(
            phase: .cancelled
          )
        }
      } catch {
        let service = self
        await MainActor.run {
          service?.progressByDirectory[dirId] = IndexingProgress(
            phase: .error(error.localizedDescription)
          )
        }
      }
      let service = self
      await MainActor.run {
        service?.activeTasks[dirId] = nil
      }
    }
  }

  /// Re-indexes all enabled directories from the given store.
  func indexAllEnabled(from store: DirectoryStore) {
    for dir in store.directories where dir.enabled {
      guard let id = dir.id, !isIndexing(id) else { continue }
      indexDirectory(dir)
    }
  }

  func cancelIndexing(_ directoryId: Int64) {
    activeTasks[directoryId]?.cancel()
    activeTasks[directoryId] = nil
  }

  // MARK: - Indexing Pipeline

  private nonisolated static func performIndexing(
    dirId: Int64,
    bookmark: Data,
    visionModelURL: URL,
    database: AppDatabase,
    onProgress: @Sendable @escaping (IndexingProgress) -> Void
  ) async throws {
    // Resolve security-scoped bookmark
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: bookmark,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }

    // Create CLIP encoder (off main thread — model loading can be slow)
    let encoder = try CLIPImageEncoder(modelPath: visionModelURL)

    // Phase 1: Quick scan — enumerate files without hashing
    onProgress(IndexingProgress(phase: .scanning))

    let defaults = UserDefaults.standard
    let skipHidden =
      defaults.object(forKey: StorageKey.ignoreHiddenDirectories) as? Bool
      ?? true
    let excludedNames: Set<String> = {
      guard let json = defaults.string(forKey: StorageKey.excludedFolderNames),
        let data = json.data(using: .utf8),
        let array = try? JSONDecoder().decode([String].self, from: data)
      else { return [] }
      return Set(array)
    }()

    let allFiles = try FileScanner.scan(
      directory: url,
      skipHiddenFiles: skipHidden,
      excludedFolderNames: excludedNames
    )

    try Task.checkCancellation()

    // Phase 2: Diff against existing indexed files
    let existingFiles: [String: Date] = try await database.dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT path, modifiedAt FROM files WHERE directoryId = ?",
        arguments: [dirId]
      )
      var dict: [String: Date] = [:]
      for row in rows {
        if let path: String = row["path"], let date: Date = row["modifiedAt"] {
          dict[path] = date
        }
      }
      return dict
    }

    // Clean up records for files that no longer exist on disk
    let scannedPaths = Set(allFiles.map(\.url.path))
    let deletedPaths = Set(existingFiles.keys).subtracting(scannedPaths)
    if !deletedPaths.isEmpty {
      try await database.dbQueue.write { db in
        for path in deletedPaths {
          try db.execute(
            sql: "DELETE FROM files WHERE path = ? AND directoryId = ?",
            arguments: [path, dirId]
          )
        }
      }
    }

    // Filter to only new or modified files.
    // The database stores dates as text with millisecond precision, so the
    // round-tripped date loses sub-millisecond information. Use a small
    // tolerance to avoid false positives from that truncation.
    let filesToProcess = allFiles.filter { file in
      guard let existingDate = existingFiles[file.url.path] else { return true }
      return file.modifiedAt.timeIntervalSince(existingDate) > 1.0
    }

    if filesToProcess.isEmpty {
      try await database.dbQueue.write { db in
        if var dir = try SharkfinDirectory.fetchOne(db, id: dirId) {
          dir.lastIndexedAt = Date()
          try dir.update(db)
        }
      }
      onProgress(IndexingProgress(phase: .upToDate))
      return
    }

    // Phase 3: Process files with bounded concurrency
    let total = filesToProcess.count
    onProgress(IndexingProgress(phase: .indexing, total: total))

    let maxConcurrency = 8
    var processed = 0

    await withTaskGroup(of: String.self) { group in
      var index = 0

      // Seed initial batch
      while index < min(maxConcurrency, filesToProcess.count) {
        let file = filesToProcess[index]
        index += 1
        group.addTask {
          Self.processFile(
            file,
            directoryId: dirId,
            encoder: encoder,
            database: database
          )
          return file.filename
        }
      }

      // As each task completes, enqueue the next file
      for await filename in group {
        if Task.isCancelled { break }
        processed += 1
        onProgress(
          IndexingProgress(
            phase: .indexing,
            total: total,
            processed: processed,
            currentFile: filename
          )
        )

        if index < filesToProcess.count {
          let file = filesToProcess[index]
          index += 1
          group.addTask {
            Self.processFile(
              file,
              directoryId: dirId,
              encoder: encoder,
              database: database
            )
            return file.filename
          }
        }
      }
    }

    try Task.checkCancellation()

    // Update directory last-indexed timestamp
    try await database.dbQueue.write { db in
      if var dir = try SharkfinDirectory.fetchOne(db, id: dirId) {
        dir.lastIndexedAt = Date()
        try dir.update(db)
      }
    }

    onProgress(
      IndexingProgress(
        phase: .complete(processed),
        total: total,
        processed: processed
      )
    )
    await NotificationCenter.default.post(
      name: .searchCacheDidInvalidate,
      object: nil
    )
  }

  // MARK: - Single File Processing

  private nonisolated static func processFile(
    _ file: QuickScannedFile,
    directoryId: Int64,
    encoder: CLIPImageEncoder,
    database: AppDatabase
  ) {
    do {
      // 1. Load image — if the file isn't a valid image, record it in the DB
      //    without an embedding so the scanner doesn't retry it every time.
      guard let image = NSImage(contentsOf: file.url) else {
        try database.dbQueue.write { db in
          try db.execute(
            sql: "DELETE FROM files WHERE path = ? AND directoryId = ?",
            arguments: [file.url.path, directoryId]
          )
          var indexedFile = IndexedFile(
            path: file.url.path,
            directoryId: directoryId,
            filename: file.filename,
            fileExtension: file.fileExtension,
            sizeBytes: file.sizeBytes,
            modifiedAt: file.modifiedAt,
            contentHash: "",
            mimeType: nil,
            width: nil,
            height: nil,
            indexedAt: Date(),
            thumbnailPath: nil
          )
          try indexedFile.insert(db)
        }
        return
      }

      // Downscale if too large for CLIP
      let maxDim: CGFloat = 4096
      let finalImage: NSImage
      if image.size.width > maxDim || image.size.height > maxDim {
        let scale = min(maxDim / image.size.width, maxDim / image.size.height)
        let newSize = NSSize(
          width: image.size.width * scale,
          height: image.size.height * scale
        )
        finalImage = NSImage(size: newSize)
        finalImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        finalImage.unlockFocus()
      } else {
        finalImage = image
      }

      // 2. Content hash (for thumbnail naming and dedup)
      let contentHash = try FileScanner.hashFile(at: file.url)

      // 3. CLIP preprocess + encode
      guard let tensorData = ImagePreprocessor.preprocess(finalImage) else {
        return
      }
      let embedding = try encoder.encode(pixelValues: tensorData)

      // 4. Generate thumbnail
      let thumbnailPath = try ThumbnailGenerator.generateThumbnail(
        for: file.url,
        contentHash: contentHash
      )

      // 5. Persist to database (single transaction)
      let embeddingData = embedding.withUnsafeBufferPointer { Data(buffer: $0) }

      try database.dbQueue.write { db in
        // Remove existing record if re-indexing a modified file
        try db.execute(
          sql: "DELETE FROM files WHERE path = ? AND directoryId = ?",
          arguments: [file.url.path, directoryId]
        )

        var indexedFile = IndexedFile(
          path: file.url.path,
          directoryId: directoryId,
          filename: file.filename,
          fileExtension: file.fileExtension,
          sizeBytes: file.sizeBytes,
          modifiedAt: file.modifiedAt,
          contentHash: contentHash,
          mimeType: nil,
          width: Int(finalImage.size.width),
          height: Int(finalImage.size.height),
          indexedAt: Date(),
          thumbnailPath: thumbnailPath
        )
        try indexedFile.insert(db)

        guard let fileId = indexedFile.id else { return }
        let fileEmbedding = FileEmbedding(
          fileId: fileId,
          embedding: embeddingData
        )
        try fileEmbedding.insert(db)
      }
    } catch {
      print("Failed to index \(file.filename): \(error)")
    }
  }
}
