import SwiftUI

struct SearchFilterButton: View {
  @Binding var selectedTypes: Set<String>
  let availableTypes: [String]

  @Environment(\.colorScheme) private var colorScheme

  private var isActive: Bool { !selectedTypes.isEmpty }

  private var buttonLabel: String {
    guard !selectedTypes.isEmpty else { return "Type" }
    let sorted = selectedTypes.sorted()
    if sorted.count <= 2 {
      return sorted.map { $0.uppercased() }.joined(separator: ", ")
    }
    return "\(sorted[0].uppercased()), +\(sorted.count - 1)"
  }

  var body: some View {
    Menu {
      ForEach(availableTypes, id: \.self) { ext in
        Button {
          if selectedTypes.contains(ext) {
            selectedTypes.remove(ext)
          } else {
            selectedTypes.insert(ext)
          }
        } label: {
          HStack {
            Text(ext.uppercased())
            Spacer()
            if selectedTypes.contains(ext) {
              Image(systemName: "checkmark")
            }
          }
        }
      }

      if !selectedTypes.isEmpty {
        Divider()
        Button("Clear Filter") {
          selectedTypes.removeAll()
        }
      }
    } label: {
      FilterButtonLabel(text: buttonLabel, isActive: isActive)
        .environment(\.colorScheme, isActive ? .dark : colorScheme)
    }
    .background(
      isActive
        ? AnyShapeStyle(Color.accentColor)
        : AnyShapeStyle(.clear),
      in: RoundedRectangle(cornerRadius: 6)
    )
    .fixedSize()
    .menuIndicator(.hidden)
  }
}

/// Shared label used by both filter buttons. The text color is controlled
/// through the environment color scheme set by the parent, while the
/// background is applied to the Menu itself (outside the label).
struct FilterButtonLabel: View {
  let text: String
  let isActive: Bool

  var body: some View {
    Text(text)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(isActive ? .primary : .secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .contentShape(RoundedRectangle(cornerRadius: 6))
  }
}
