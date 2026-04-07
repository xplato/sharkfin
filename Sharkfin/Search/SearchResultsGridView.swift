import SwiftUI

struct SearchResultsGridView: View {
  let results: [SearchResult]
  var hasMore: Bool = false
  var onShowMore: (() -> Void)?

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

      if hasMore {
        Button {
          onShowMore?()
        } label: {
          Text("Show More Results")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
      }
    }
  }
}
