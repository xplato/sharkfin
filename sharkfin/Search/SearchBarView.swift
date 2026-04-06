import SwiftUI

struct SearchBarView: View {
  @Bindable var viewModel: SearchViewModel
  var onSubmit: () -> Void
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void
  @Environment(DirectoryStore.self) private var directoryStore

  private var allDirectoriesDisabled: Bool {
    !directoryStore.directories.isEmpty
      && !directoryStore.directories.contains(where: \.enabled)
  }

  var body: some View {
    HStack(spacing: 12) {
      if allDirectoriesDisabled {
        Button {
          onOpenSettings()
        } label: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .font(.title2)
        }
        .buttonStyle(.plain)
        .help("All directories are disabled. Click to open settings.")
      } else {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.title2)
      }

      TextField(
        allDirectoriesDisabled ? "All directories disabled" : "Search files...",
        text: $viewModel.query
      )
      .textFieldStyle(.plain)
      .font(.title3)
      .onSubmit { onSubmit() }
      .disabled(allDirectoriesDisabled)

      if viewModel.state == .searching {
        ProgressView()
          .controlSize(.small)
      }

      Button {
        onOpenSettings()
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
