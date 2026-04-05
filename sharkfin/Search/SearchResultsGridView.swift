import SwiftUI

struct SearchResultsGridView: View {
  let results: [SearchResult]
  var onResultTapped: (SearchResult) -> Void

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 12),
    count: 4
  )

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(results) { result in
          SearchResultCell(result: result)
            .onTapGesture { onResultTapped(result) }
        }
      }
      .padding(12)
    }
  }
}

struct SearchResultCell: View {
  let result: SearchResult

  var body: some View {
    VStack(spacing: 6) {
      Group {
        if let thumbnailPath = result.thumbnailPath,
           let nsImage = NSImage(contentsOfFile: thumbnailPath) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(.quaternary)
            .overlay {
              Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.tertiary)
            }
        }
      }
      .frame(height: 100)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      Text(result.filename)
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.primary)
    }
  }
}
