import SwiftUI

struct SearchBarView: View {
  @Bindable var viewModel: SearchViewModel
  var onSubmit: () -> Void
  var onDismiss: () -> Void
  
  @Environment(DirectoryStore.self) private var directoryStore
  @State private var stats: AppDatabase.Stats?

  private var allDirectoriesDisabled: Bool {
    !directoryStore.directories.isEmpty
      && !directoryStore.directories.contains(where: \.enabled)
  }

  var body: some View {
    HStack(spacing: 12) {
      if allDirectoriesDisabled {
        SettingsLink {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .font(.title2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
          onDismiss()
          NSApplication.shared.activate(ignoringOtherApps: true)
        })
        .help("All directories are disabled. Click to open settings.")
      } else {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.title2)
      }

      TextField(
        allDirectoriesDisabled ? "All directories disabled" : "Search \(stats?.totalFiles ?? 0) files...",
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
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .task {
      stats = try? AppDatabase.shared.fetchStats()
    }
  }
}
