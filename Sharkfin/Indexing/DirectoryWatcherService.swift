import CoreServices
import Foundation
import Observation

@MainActor
@Observable
final class DirectoryWatcherService {
  private(set) var isWatching = false
  
  private var stream: FSEventStreamRef?
  private var debounceTasks: [Int64: Task<Void, Never>] = [:]
  private weak var indexingService: IndexingService?
  private weak var directoryStore: DirectoryStore?
  
  /// Maps watched root paths back to their directory ID for fast lookup
  /// when FSEvents fires.
  private var pathToDirectoryId: [String: Int64] = [:]
  
  private let debounceInterval: Duration = .seconds(3)
  
  func start(
    directoryStore: DirectoryStore,
    indexingService: IndexingService
  ) {
    self.directoryStore = directoryStore
    self.indexingService = indexingService
    restartIfNeeded()
  }
  
  func stop() {
    stopStream()
    for task in debounceTasks.values { task.cancel() }
    debounceTasks.removeAll()
  }
  
  /// Call when the watched-directories list or the toggle changes.
  func restartIfNeeded() {
    let enabled =
    UserDefaults.standard.object(forKey: StorageKey.watchDirectories) as? Bool
    ?? true
    guard enabled,
          let store = directoryStore,
          !store.directories.isEmpty
    else {
      stopStream()
      return
    }
    
    let watchedDirs = store.directories.filter {
      $0.enabled && $0.bookmark != nil
    }
    guard !watchedDirs.isEmpty else {
      stopStream()
      return
    }
    
    // Rebuild path → id mapping
    pathToDirectoryId.removeAll()
    var resolvedPaths: [String] = []
    
    for dir in watchedDirs {
      guard let id = dir.id, let bookmark = dir.bookmark else { continue }
      var isStale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: bookmark,
          options: .withSecurityScope,
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
      else { continue }
      
      let path = url.path(percentEncoded: false)
      pathToDirectoryId[path] = id
      resolvedPaths.append(path)
    }
    
    guard !resolvedPaths.isEmpty else {
      stopStream()
      return
    }
    
    // Tear down old stream before creating a new one
    stopStream()
    startStream(paths: resolvedPaths)
  }
  
  // MARK: - FSEvents
  
  private func startStream(paths: [String]) {
    let cfPaths = paths as CFArray
    
    // We pass `self` (MainActor-isolated) through the context pointer.
    // The callback dispatches back to MainActor before touching any state.
    var context = FSEventStreamContext()
    context.info = Unmanaged.passUnretained(self).toOpaque()
    
    let callback: FSEventStreamCallback = {
      (
        streamRef,
        clientCallBackInfo,
        numEvents,
        eventPaths,
        eventFlags,
        eventIds
      ) in
      guard let clientCallBackInfo else { return }
      
      let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths)
        .takeUnretainedValue()
      var paths: [String] = []
      for i in 0..<numEvents {
        if let path = unsafeBitCast(
          CFArrayGetValueAtIndex(cfArray, i),
          to: CFString?.self
        ) as String? {
          paths.append(path)
        }
      }
      
      let service = Unmanaged<DirectoryWatcherService>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
      
      Task { @MainActor in
        service.handleFSEvents(paths: paths)
      }
    }
    
    guard
      let stream = FSEventStreamCreate(
        nil,
        callback,
        &context,
        cfPaths,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        1.0,  // latency — FSEvents already coalesces within this window
        FSEventStreamCreateFlags(
          kFSEventStreamCreateFlagUseCFTypes
          | kFSEventStreamCreateFlagFileEvents
          | kFSEventStreamCreateFlagNoDefer
        )
      )
    else { return }
    
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
    self.stream = stream
    isWatching = true
  }
  
  private func stopStream() {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
    isWatching = false
  }
  
  // MARK: - Event Handling
  
  /// Called from the FSEvents C callback on the main thread.
  fileprivate func handleFSEvents(paths: [String]) {
    guard let indexingService, let directoryStore else { return }
    
    // Figure out which tracked directories were affected
    var affectedIds: Set<Int64> = []
    for eventPath in paths {
      for (watchedRoot, dirId) in pathToDirectoryId {
        if eventPath.hasPrefix(watchedRoot) {
          affectedIds.insert(dirId)
          break
        }
      }
    }
    
    for dirId in affectedIds {
      // Cancel any pending debounce for this directory and restart it
      debounceTasks[dirId]?.cancel()
      debounceTasks[dirId] = Task {
        [weak self, weak indexingService, weak directoryStore] in
        do {
          try await Task.sleep(for: self?.debounceInterval ?? .seconds(3))
        } catch { return }  // cancelled
        
        guard let indexingService, let directoryStore else { return }
        guard
          let dir = directoryStore.directories.first(where: { $0.id == dirId })
        else { return }
        
        // Only trigger if not already indexing
        guard !indexingService.isIndexing(dirId) else { return }
        indexingService.indexDirectory(dir)
        
        self?.debounceTasks[dirId] = nil
      }
    }
  }
}
