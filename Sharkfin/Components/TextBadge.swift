import SwiftUI

struct TextBadge: View {
  let text: String
  let color: Color
  
  var body: some View {
    Text(text)
      .font(.caption2)
      .fontWeight(.medium)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }
}
