import SwiftUI

struct SearchResultCard: View {
  let result: SearchResult
  @Environment(SearchController.self) private var searchController
  @State private var isHovering = false

  var body: some View {
    VStack(spacing: 4) {
      // Thumbnail
      if let thumbPath = result.thumbnailPath,
        let nsImage = NSImage(contentsOfFile: thumbPath)
      {
        Color.clear
          .aspectRatio(1, contentMode: .fit)
          .overlay {
            Image(nsImage: nsImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
          }
          .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 8,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 8
          ))
          .background(
            Color.primary.opacity(0.06),
            in: UnevenRoundedRectangle(
              topLeadingRadius: 8,
              bottomLeadingRadius: 0,
              bottomTrailingRadius: 0,
              topTrailingRadius: 8
            )
          )
      } else {
        RoundedRectangle(cornerRadius: 6)
          .fill(.quaternary)
          .aspectRatio(1, contentMode: .fit)
          .overlay {
            Image(systemName: "photo")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
      }

      // File info
      HStack(spacing: 4) {
        Text(result.filename)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(isHovering ? .primary : .secondary)
      }
      .padding(.horizontal, 6)
    }
    .padding(.bottom, 6)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isHovering ? .white.opacity(0.08) : .clear)
    )
    .onHover { hovering in
      isHovering = hovering
    }
    .onTapGesture {
      searchController.selectResult(result)
    }
    .help(result.path)
  }
}
