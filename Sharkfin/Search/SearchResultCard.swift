import SwiftUI

struct SearchResultCard: View {
  let result: SearchResult
  @Environment(SearchController.self) private var searchController
  @State private var isHovering = false

  private let cornerRadius: CGFloat = 8

  var body: some View {
    CardThumbnail(result: result, cornerRadius: cornerRadius)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(.primary.opacity(isHovering ? 0.3 : 0))
      )
      .scaleEffect(isHovering ? 1.05 : 1.0)
      .contentShape(Rectangle())
      .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.2)) {
          isHovering = hovering
        }
      }
      .onTapGesture {
        searchController.selectResult(result)
      }
      .help(formatDisplayPath(result.path))
  }
}

/// Extracted so that the thumbnail doesn't re-evaluate when hover state changes.
private struct CardThumbnail: View {
  let result: SearchResult
  let cornerRadius: CGFloat

  var body: some View {
    if let thumbPath = result.thumbnailPath,
       let nsImage = NSImage(contentsOfFile: thumbPath)
    {
      Color.clear
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .background(
          Color.primary.opacity(0),
          in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    } else {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(.quaternary)
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.secondary)
        }
    }
  }
}
