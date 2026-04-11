import Foundation

enum SearchState: Equatable {
  case idle
  case searching
  case results
  case noResults
}

struct SearchResult: Identifiable, Equatable {
  let id: Int64
  let filename: String
  let path: String
  let thumbnailPath: String?
  let rawScore: Float
  let relevance: Float
}

@MainActor
@Observable
final class SearchViewModel {
  var query: String = ""
  var filters = SearchFilters()
  private(set) var state: SearchState = .idle
  private(set) var results: [SearchResult] = []
  private(set) var availableFileTypes: [String] = []
  
  private var displayLimit: Int = SearchViewModel.pageSize()
  
  var displayedResults: [SearchResult] {
    Array(results.prefix(displayLimit))
  }
  
  var hasMoreResults: Bool {
    results.count > displayLimit
  }
  
  func showMoreResults() {
    displayLimit += Self.pageSize()
  }
  
  /// Returns a page size close to 50 that is evenly divisible by the column count.
  private static func pageSize() -> Int {
    let columns = UserDefaults.standard.integer(
      forKey: StorageKey.searchResultColumns
    )
    let count = (3...5).contains(columns) ? columns : 4
    return (50 / count) * count
  }
  
  private let database: AppDatabase
  private let modelManager: CLIPModelManager
  private var searchService: SearchService?
  private var searchServiceTask: Task<SearchService, any Error>?
  private var searchTask: Task<Void, Never>?
  private var idleUnloadTask: Task<Void, Never>?
  
  /// How long to keep the text encoder in memory after the last search.
  /// Shorter on low-RAM machines to reduce memory pressure.
  private static let idleUnloadDelay: Duration = {
    let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
    if ramGB <= 8 { return .seconds(180) }
    if ramGB <= 16 { return .seconds(600) }
    return .seconds(1800)
  }()
  
  init(database: AppDatabase, modelManager: CLIPModelManager) {
    self.database = database
    self.modelManager = modelManager
  }
  
  func loadAvailableFileTypes() async {
    let types = (try? await database.fetchAvailableFileTypes()) ?? []
    availableFileTypes = types
    // Remove any selected types that are no longer available
    let pruned = filters.fileTypes.intersection(availableFileTypes)
    if pruned != filters.fileTypes {
      filters.fileTypes = pruned
    }
  }
  
  func filtersChanged() {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    searchTask?.cancel()
    searchTask = Task {
      await executeSearch(trimmed)
    }
  }
  
  /// Called by the view on each query change to debounce search.
  func queryChanged() {
    searchTask?.cancel()
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      results = []
      state = .idle
      return
    }
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(50))
      guard !Task.isCancelled else { return }
      await executeSearch(trimmed)
    }
  }
  
  /// Called on Enter to skip debounce and search immediately.
  func submitSearch() {
    searchTask?.cancel()
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    searchTask = Task {
      await executeSearch(trimmed)
    }
  }
  
  func clearSearch() {
    searchTask?.cancel()
    query = ""
    results = []
    displayLimit = Self.pageSize()
    state = .idle
  }
  
  // MARK: - Private
  
  private func executeSearch(_ query: String) async {
    state = .searching
    displayLimit = Self.pageSize()
    let currentFilters = filters
    do {
      let service = try await getOrCreateSearchService()
      guard !Task.isCancelled else { return }
      let searchResults = try await Task.detached(priority: .userInitiated) {
        try await service.search(query: query, filters: currentFilters)
      }.value
      guard !Task.isCancelled else { return }
      results = searchResults
      state = searchResults.isEmpty ? .noResults : .results
      scheduleIdleUnload()
    } catch is CancellationError {
      // Keep previous results on cancellation
    } catch {
      guard !Task.isCancelled else { return }
      LoggingService.shared.info("Error: \(error)", category: "Search")
      results = []
      state = .noResults
    }
  }
  
  /// After a period of inactivity, release the text encoder and embedding
  /// cache to reclaim ~450MB. The next search will recreate them.
  private func scheduleIdleUnload() {
    idleUnloadTask?.cancel()
    idleUnloadTask = Task { [weak self] in
      try? await Task.sleep(for: Self.idleUnloadDelay)
      guard !Task.isCancelled else { return }
      self?.unloadSearchService()
    }
  }
  
  private func unloadSearchService() {
    searchService = nil
    searchServiceTask = nil
    LoggingService.shared.info(
      "Unloaded search service after idle timeout",
      category: "Search"
    )
  }
  
  private func getOrCreateSearchService() async throws -> SearchService {
    if let existing = searchService { return existing }
    if let task = searchServiceTask { return try await task.value }
    
    let db = database
    let mm = modelManager
    let task = Task<SearchService, any Error> {
      guard let modelURL = mm.textModelURL,
            let tokenizerURL = mm.textTokenizerFolderURL
      else {
        throw CLIPError.modelNotReady
      }
      let activePackage = mm.activePackage
      let encoder = try await CLIPTextEncoder(
        modelPath: modelURL,
        tokenizerFolder: tokenizerURL,
        embeddingDimension: activePackage.embeddingDimension
      )
      return SearchService(
        database: db,
        textEncoder: encoder,
        modelId: activePackage.id
      )
    }
    searchServiceTask = task
    let service = try await task.value
    searchService = service
    searchServiceTask = nil
    return service
  }
}
