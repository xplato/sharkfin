import SwiftUI

struct SearchFilterButton: View {
  @Binding var selectedTypes: Set<String>
  let availableTypes: [String]
  
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
      Text(buttonLabel)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(isActive ? .white : .secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
