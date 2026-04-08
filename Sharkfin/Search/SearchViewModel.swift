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
  private var searchTask: Task<Void, Never>?

  init(database: AppDatabase, modelManager: CLIPModelManager) {
    self.database = database
    self.modelManager = modelManager
  }

  func loadAvailableFileTypes() async {
    let types = (try? await database.fetchAvailableFileTypes()) ?? []
    availableFileTypes = types
    // Remove any selected types that are no longer available
    filters.fileTypes.formIntersection(availableFileTypes)
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
      let searchResults = try await Task.detached(priority: .userInitiated) {
        try await service.search(query: query, filters: currentFilters)
      }.value
      guard !Task.isCancelled else { return }
      results = searchResults
      state = searchResults.isEmpty ? .noResults : .results
    } catch is CancellationError {
      // Keep previous results on cancellation
    } catch {
      guard !Task.isCancelled else { return }
      LoggingService.shared.info("Error: \(error)", category: "Search")
      results = []
      state = .noResults
    }
  }

  private func getOrCreateSearchService() async throws -> SearchService {
    if let existing = searchService { return existing }
    guard let modelURL = modelManager.textModelURL,
      let tokenizerURL = modelManager.textTokenizerFolderURL
    else {
      throw CLIPError.modelNotReady
    }
    let encoder = try await CLIPTextEncoder(
      modelPath: modelURL,
      tokenizerFolder: tokenizerURL
    )
    let service = SearchService(database: database, textEncoder: encoder)
    searchService = service
    return service
  }
}
