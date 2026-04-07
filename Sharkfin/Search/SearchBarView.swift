import SwiftUI

private struct SpinnerView: View {
  @State private var rotation = 0.0

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.7)
      .stroke(
        AngularGradient(
          gradient: Gradient(colors: [
            Color.accentColor.opacity(0), .accentColor,
          ]),
          center: .center,
          startAngle: .zero,
          endAngle: .degrees(252)
        ),
        style: StrokeStyle(lineWidth: 3, lineCap: .round)
      )
      .frame(width: 18, height: 18)
      .rotationEffect(.degrees(rotation))
      .onAppear {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false))
        {
          rotation = 360
        }
      }
  }
}

struct SearchBarView: View {
  @Bindable var viewModel: SearchViewModel
  var onSubmit: () -> Void
  var onDismiss: () -> Void

  @Environment(DirectoryStore.self) private var directoryStore
  @State private var enabledFileCount: Int = 0

  private var allDirectoriesDisabled: Bool {
    !directoryStore.directories.isEmpty
      && !directoryStore.directories.contains(where: \.enabled)
  }

  var body: some View {
    HStack(spacing: 12) {
      if !directoryStore.directories.isEmpty {
        DirectoryScopeButton(scope: $viewModel.filters.directoryScope)
      }

      if allDirectoriesDisabled {
        SettingsLink {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .font(.title2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
          TapGesture().onEnded {
            onDismiss()
            NSApplication.shared.activate(ignoringOtherApps: true)
          }
        )
        .help("All directories are disabled. Click to open settings.")
      } else {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.title2)
      }

      TextField(
        allDirectoriesDisabled
          ? "All directories disabled"
          : "Search \(enabledFileCount) files...",
        text: $viewModel.query
      )
      .textFieldStyle(.plain)
      .font(.title3)
      .onSubmit { onSubmit() }
      .disabled(allDirectoriesDisabled)

      if viewModel.state == .searching {
        SpinnerView()
          .transition(.identity)
      }

      if !viewModel.availableFileTypes.isEmpty {
        SearchFilterButton(
          selectedTypes: $viewModel.filters.fileTypes,
          availableTypes: viewModel.availableFileTypes
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .task {
      enabledFileCount = (try? AppDatabase.shared.fetchEnabledFileCount()) ?? 0
      viewModel.loadAvailableFileTypes()
    }
    .onChange(of: directoryStore.directories) {
      enabledFileCount = (try? AppDatabase.shared.fetchEnabledFileCount()) ?? 0
      viewModel.loadAvailableFileTypes()
    }
    .onChange(of: viewModel.filters) {
      viewModel.filtersChanged()
    }
  }
}
