import SwiftUI

struct SearchResultsGridView: View {
  let results: [SearchResult]

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 12),
    count: 4
  )

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(results) { result in
          SearchResultCard(result: result)
        }
      }
      .padding(12)
    }
  }
}
