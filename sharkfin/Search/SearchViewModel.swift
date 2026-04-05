import Foundation

enum SearchState: Equatable {
  case idle
  case searching
  case results
  case noResults
}

struct SearchResult: Identifiable {
  let id: Int64
  let filename: String
  let thumbnailPath: String?
  let path: String
}

@MainActor
@Observable
final class SearchViewModel {
  var query: String = ""
  private(set) var state: SearchState = .idle
  private(set) var results: [SearchResult] = []

  var onStateChange: (() -> Void)?

  /// Called when user presses Enter.
  /// Stubbed with mock data for now.
  func performSearch() {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      clearSearch()
      return
    }

    state = .searching
    onStateChange?()

    // Mock search with a short delay
    Task {
      try? await Task.sleep(for: .milliseconds(300))
      let mockResults = Self.makeMockResults(for: trimmed)
      if mockResults.isEmpty {
        results = []
        state = .noResults
      } else {
        results = mockResults
        state = .results
      }
      onStateChange?()
    }
  }

  func clearSearch() {
    query = ""
    results = []
    state = .idle
    onStateChange?()
  }

  // Mock: typing "empty" returns no results; anything else returns 8 items.
  private static func makeMockResults(for query: String) -> [SearchResult] {
    if query.lowercased().contains("empty") { return [] }

    return (1...8).map { i in
      SearchResult(
        id: Int64(i),
        filename: "photo_\(i).jpg",
        thumbnailPath: nil,
        path: "/mock/path/photo_\(i).jpg"
      )
    }
  }
}
