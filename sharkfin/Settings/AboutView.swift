import SwiftUI

struct AboutView: View {
  var body: some View {
    VStack(spacing: 8) {
      Text("Sharkfin")
        .font(.largeTitle)
        .lineSpacing(50)
        .lineLimit(nil)
      
      Text("This is the caption text below the title.")
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .multilineTextAlignment(.center)
  }
}
