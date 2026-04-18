import Foundation

@MainActor
@Observable
final class SearchController {
  private(set) var selectedResult: SearchResult?
  var hidePanel: (() -> Void)?
  
  func selectResult(_ result: SearchResult) {
    selectedResult = result
  }
  
  func clearSelection() {
    selectedResult = nil
  }
}
