import SwiftUI

struct SearchBarView: View {
  @Bindable var viewModel: SearchViewModel
  var onSubmit: () -> Void
  var onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .font(.title2)

      TextField("Search files...", text: $viewModel.query)
        .textFieldStyle(.plain)
        .font(.title3)
        .onSubmit { onSubmit() }

      if viewModel.state == .searching {
        ProgressView()
          .controlSize(.small)
      }

      SettingsLink {
        Image(systemName: "ellipsis")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .simultaneousGesture(TapGesture().onEnded { onDismiss() })
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
