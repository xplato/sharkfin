import SwiftUI

struct SearchResultCard: View {
  let result: SearchResult
  @Environment(SearchController.self) private var searchController
  @State private var isHovering = false
  @State private var mousePosition: CGPoint = .zero
  
  private let cornerRadius: CGFloat = 8
  
  var body: some View {
    CardThumbnail(result: result, cornerRadius: cornerRadius)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(.primary.opacity(0))
      )
      .contentShape(Rectangle())
      .overlay {
        GlassHighlightBorder(
          mousePosition: mousePosition,
          isHovering: isHovering,
          cornerRadius: cornerRadius
        )
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          mousePosition = location
          if !isHovering {
            withAnimation(.easeIn(duration: 0.15)) {
              isHovering = true
            }
          }
        case .ended:
          withAnimation(.easeOut(duration: 0.3)) {
            isHovering = false
          }
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

private struct GlassHighlightBorder: View {
  var mousePosition: CGPoint
  var isHovering: Bool
  var cornerRadius: CGFloat
  @Environment(\.colorScheme) private var colorScheme
  
  private var peakOpacity: Double { colorScheme == .dark ? 0.6 : 0.3 }
  private var midOpacity: Double { colorScheme == .dark ? 0.15 : 0.08 }
  
  var body: some View {
    GeometryReader { geo in
      let size = geo.size
      let center = UnitPoint(
        x: size.width > 0 ? mousePosition.x / size.width : 0.5,
        y: size.height > 0 ? mousePosition.y / size.height : 0.5
      )
      
      // Soft base border, always visible
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(.primary.opacity(0.1), lineWidth: 1)
      
      // Specular highlight that follows the cursor
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(
          RadialGradient(
            colors: [
              .primary.opacity(isHovering ? peakOpacity : 0),
              .primary.opacity(isHovering ? midOpacity : 0),
              .clear,
            ],
            center: center,
            startRadius: 0,
            endRadius: size.width * 0.7
          ),
          lineWidth: 1.5
        )
        .animation(.linear(duration: 0.05), value: mousePosition)
    }
  }
}
