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
  private(set) var state: SearchState = .idle
  private(set) var results: [SearchResult] = []

  private let database: AppDatabase
  private let modelManager: CLIPModelManager
  private var searchService: SearchService?
  private var searchTask: Task<Void, Never>?

  init(database: AppDatabase, modelManager: CLIPModelManager) {
    self.database = database
    self.modelManager = modelManager
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
    state = .idle
  }

  // MARK: - Private

  private func executeSearch(_ query: String) async {
    state = .searching
    do {
      let service = try await getOrCreateSearchService()
      let searchResults = try await Task.detached(priority: .userInitiated) {
        try await service.search(query: query)
      }.value
      guard !Task.isCancelled else { return }
      results = searchResults
      state = searchResults.isEmpty ? .noResults : .results
    } catch is CancellationError {
      // Keep previous results on cancellation
    } catch {
      guard !Task.isCancelled else { return }
      print("[Search] Error: \(error)")
      results = []
      state = .noResults
    }
  }

  private func getOrCreateSearchService() async throws -> SearchService {
    if let existing = searchService { return existing }
    guard let modelURL = modelManager.textModelURL,
          let tokenizerURL = modelManager.textTokenizerFolderURL else {
      throw CLIPError.modelNotReady
    }
    let encoder = try await CLIPTextEncoder(
      modelPath: modelURL, tokenizerFolder: tokenizerURL
    )
    let service = SearchService(database: database, textEncoder: encoder)
    searchService = service
    return service
  }
}
