import SwiftUI

struct SearchBarView: View {
  @Bindable var viewModel: SearchViewModel
  var onSubmit: () -> Void
  var onSettingsTapped: () -> Void

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

      Button {
        onSettingsTapped()
      } label: {
        Image(systemName: "ellipsis")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
