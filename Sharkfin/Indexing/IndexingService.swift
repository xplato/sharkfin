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
    
    let activePackage = modelManager.activePackage
    
    progressByDirectory[dirId] = IndexingProgress(phase: .scanning)
    
    let db = database
    activeTasks[dirId] = Task.detached { [weak self] in
      let startTime = ContinuousClock.now
      do {
        try await Self.performIndexing(
          dirId: dirId,
          bookmark: bookmark,
          visionModelURL: visionModelURL,
          modelPackage: activePackage,
          database: db
        ) { [weak self] progress in
          let service = self
          Task { @MainActor in
            service?.progressByDirectory[dirId] = progress
          }
        }
        let elapsed = ContinuousClock.now - startTime
        LoggingService.shared.debug(
          "Directory \(dirId) indexed in \(elapsed)",
          category: "Indexing"
        )
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
    modelPackage: CLIPModelPackage,
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
    let encoder = try CLIPImageEncoder(
      modelPath: visionModelURL,
      embeddingDimension: modelPackage.embeddingDimension
    )
    
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
    
    // Phase 2: Diff against all existing indexed files (across directories)
    // so we can detect overlapping files owned by a different directory
    // and files that lack an embedding for the active model.
    let activeModelId = modelPackage.id
    let (existingFiles, existingOwners) = try await database.dbQueue.read {
      db -> ([String: (date: Date, fileId: Int64, hasActiveEmbed: Bool)], [String: Int64]) in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT f.id AS fileId, f.path, f.modifiedAt, f.directoryId,
                 EXISTS(SELECT 1 FROM fileEmbeddings e
                        WHERE e.fileId = f.id AND e.modelId = ?) AS hasActiveEmbed
          FROM files f
          """,
        arguments: [activeModelId]
      )
      var files: [String: (date: Date, fileId: Int64, hasActiveEmbed: Bool)] = [:]
      var owners: [String: Int64] = [:]
      for row in rows {
        if let path: String = row["path"],
           let date: Date = row["modifiedAt"],
           let ownerId: Int64 = row["directoryId"],
           let fileId: Int64 = row["fileId"] {
          let hasEmbed: Bool = row["hasActiveEmbed"]
          files[path] = (date: date, fileId: fileId, hasActiveEmbed: hasEmbed)
          owners[path] = ownerId
        }
      }
      return (files, owners)
    }
    
    // Clean up records for files owned by this directory that no longer exist on disk
    let scannedPaths = Set(allFiles.map(\.url.path))
    let ownedPaths = Set(existingOwners.filter { $0.value == dirId }.keys)
    let deletedPaths = ownedPaths.subtracting(scannedPaths)
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
    
    // Remove indexed files that now fall under excluded folders.
    // The scan-diff above should catch these, but an explicit DB query
    // guards against path-format mismatches between scanner URLs and
    // stored paths.
    if !excludedNames.isEmpty {
      try await database.dbQueue.write { db in
        for name in excludedNames {
          let pattern = "%/" + name + "/%"
          try db.execute(
            sql: "DELETE FROM files WHERE directoryId = ? AND path LIKE ?",
            arguments: [dirId, pattern]
          )
        }
      }
    }
    
    // Fetch the set of enabled directory IDs so we only reassign files from
    // directories that have been removed or disabled (not from active peers).
    let enabledDirIds: Set<Int64> = try await database.dbQueue.read { db in
      let ids = try Int64.fetchAll(
        db,
        sql: "SELECT id FROM directories WHERE enabled = 1"
      )
      return Set(ids)
    }
    
    // Categorize scanned files into four tiers:
    // 1. New or modified → full processing pipeline (deletes old file + all embeddings)
    // 2. Unchanged but missing embedding for active model → generate embedding only
    // 3. Unchanged but owned by a removed/disabled directory → cheap reassignment
    // 4. Unchanged with active-model embedding → skip
    var filesToProcess: [QuickScannedFile] = []
    var filesToEmbed: [(file: QuickScannedFile, fileId: Int64)] = []
    var pathsToReassign: [String] = []
    
    for file in allFiles {
      guard let existing = existingFiles[file.url.path] else {
        filesToProcess.append(file)
        continue
      }
      // The database stores dates as text with millisecond precision, so the
      // round-tripped date loses sub-millisecond information. Use a small
      // tolerance to avoid false positives from that truncation.
      let isModified = file.modifiedAt.timeIntervalSince(existing.date) > 1.0
      let currentOwner = existingOwners[file.url.path]
      let ownedByOther = currentOwner != dirId
      
      if isModified {
        filesToProcess.append(file)
      } else if !existing.hasActiveEmbed {
        filesToEmbed.append((file: file, fileId: existing.fileId))
      } else if ownedByOther, let owner = currentOwner, !enabledDirIds.contains(owner) {
        pathsToReassign.append(file.url.path)
      }
    }
    
    // Reassign unchanged files that were previously owned by another directory
    let reassignPaths = pathsToReassign
    if !reassignPaths.isEmpty {
      LoggingService.shared.info(
        "Reassigning \(reassignPaths.count) file(s) from other directories to directory \(dirId)",
        category: "Indexing"
      )
      try await database.dbQueue.write { db in
        for path in reassignPaths {
          try db.execute(
            sql: "UPDATE files SET directoryId = ? WHERE path = ?",
            arguments: [dirId, path]
          )
        }
      }
    }
    
    if filesToProcess.isEmpty && filesToEmbed.isEmpty {
      try await database.dbQueue.write { db in
        if var dir = try SharkfinDirectory.fetchOne(db, id: dirId) {
          dir.lastIndexedAt = Date()
          try dir.update(db)
        }
      }
      // Invalidate search cache when files were removed (e.g. newly excluded
      // folders) even though there is nothing new to process.
      if !deletedPaths.isEmpty || !excludedNames.isEmpty {
        await MainActor.run {
          NotificationCenter.default.post(
            name: .searchCacheDidInvalidate,
            object: nil
          )
        }
      }
      onProgress(IndexingProgress(phase: .upToDate))
      return
    }
    
    // Phase 3: Process files with bounded concurrency
    let total = filesToProcess.count + filesToEmbed.count
    onProgress(IndexingProgress(phase: .indexing, total: total))
    
    let maxConcurrency = 8
    var processed = 0
    
    // Combine both queues into a single work list with a tag
    // to distinguish full-process from embedding-only items.
    enum WorkItem {
      case full(QuickScannedFile)
      case embedOnly(file: QuickScannedFile, fileId: Int64)
      
      var filename: String {
        switch self {
        case .full(let f): f.filename
        case .embedOnly(let f, _): f.filename
        }
      }
    }
    
    var workItems: [WorkItem] = filesToProcess.map { .full($0) }
    workItems += filesToEmbed.map { .embedOnly(file: $0.file, fileId: $0.fileId) }
    
    await withTaskGroup(of: String.self) { group in
      var index = 0
      
      func enqueue(_ item: WorkItem, in group: inout TaskGroup<String>) {
        switch item {
        case .full(let file):
          group.addTask {
            Self.processFile(
              file,
              directoryId: dirId,
              encoder: encoder,
              modelId: activeModelId,
              database: database
            )
            return file.filename
          }
        case .embedOnly(let file, let fileId):
          group.addTask {
            Self.addEmbedding(
              for: file,
              fileId: fileId,
              encoder: encoder,
              modelId: activeModelId,
              database: database
            )
            return file.filename
          }
        }
      }
      
      // Seed initial batch
      while index < min(maxConcurrency, workItems.count) {
        enqueue(workItems[index], in: &group)
        index += 1
      }
      
      // As each task completes, enqueue the next item
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
        
        if index < workItems.count {
          enqueue(workItems[index], in: &group)
          index += 1
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
    await MainActor.run {
      NotificationCenter.default.post(
        name: .searchCacheDidInvalidate,
        object: nil
      )
    }
  }
  
  // MARK: - Single File Processing
  
  private nonisolated static func processFile(
    _ file: QuickScannedFile,
    directoryId: Int64,
    encoder: CLIPImageEncoder,
    modelId: String,
    database: AppDatabase
  ) {
    do {
      // 1. Load image — if the file isn't a valid image, record it in the DB
      //    without an embedding so the scanner doesn't retry it every time.
      guard let image = NSImage(contentsOf: file.url) else {
        try database.dbQueue.write { db in
          try db.execute(
            sql: "DELETE FROM files WHERE path = ?",
            arguments: [file.url.path]
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
          sql: "DELETE FROM files WHERE path = ?",
          arguments: [file.url.path]
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
          embedding: embeddingData,
          modelId: modelId
        )
        try fileEmbedding.insert(db)
      }
    } catch {
      LoggingService.shared.info(
        "Failed to index \(file.filename): \(error)",
        category: "Indexing"
      )
    }
  }
  
  // MARK: - Embedding-Only Processing
  
  /// Generates and inserts an embedding for an existing file record.
  /// Used when the file content hasn't changed but an embedding for the
  /// active model doesn't exist yet.
  private nonisolated static func addEmbedding(
    for file: QuickScannedFile,
    fileId: Int64,
    encoder: CLIPImageEncoder,
    modelId: String,
    database: AppDatabase
  ) {
    do {
      guard let image = NSImage(contentsOf: file.url) else { return }
      
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
      
      guard let tensorData = ImagePreprocessor.preprocess(finalImage) else {
        return
      }
      let embedding = try encoder.encode(pixelValues: tensorData)
      let embeddingData = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
      
      try database.dbQueue.write { db in
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO fileEmbeddings (fileId, embedding, modelId)
            VALUES (?, ?, ?)
            """,
          arguments: [fileId, embeddingData, modelId]
        )
      }
    } catch {
      LoggingService.shared.info(
        "Failed to add embedding for \(file.filename): \(error)",
        category: "Indexing"
      )
    }
  }
}
