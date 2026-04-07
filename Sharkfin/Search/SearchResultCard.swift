import SwiftUI

struct SearchResultCard: View {
  let result: SearchResult
  @Environment(SearchController.self) private var searchController
  @State private var isHovering = false
  
  var body: some View {
    Group {
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
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
          )
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(.quaternary)
          .aspectRatio(1, contentMode: .fit)
          .overlay {
            Image(systemName: "photo")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
      }
    }
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
