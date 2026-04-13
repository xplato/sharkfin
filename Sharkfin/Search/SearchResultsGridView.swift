import SwiftUI

struct SearchResultsGridView: View {
  let results: [SearchResult]
  var hasMore: Bool = false
  var scrollToTopToken: String = ""
  var onShowMore: (() -> Void)?
  
  @AppStorage(StorageKey.searchResultColumns) private var columnCount = 4
  
  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
  }
  
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(results) { result in
            SearchResultCard(result: result)
          }
        }
        .padding(16)
        .id("resultsTop")
        
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
      .onChange(of: scrollToTopToken) {
        withAnimation {
          proxy.scrollTo("resultsTop", anchor: .top)
        }
      }
    }
  }
}
