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
  var isSearchFieldFocused: FocusState<Bool>.Binding
  
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(SearchController.self) private var searchController
  @State private var enabledFileCount: Int = 0
  
  private var allDirectoriesDisabled: Bool {
    !directoryStore.directories.isEmpty
    && !directoryStore.directories.contains(where: \.enabled)
  }
  
  var body: some View {
    HStack(spacing: 12) {
      if searchController.selectedResult != nil {
        Button {
          searchController.clearSelection()
          isSearchFieldFocused.wrappedValue = true
        } label: {
          Image(systemName: "chevron.left")
            .foregroundStyle(.secondary)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to results")
      } else if allDirectoriesDisabled {
        SettingsLink {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .font(.system(size: 18))
            .frame(width: 22, height: 22)
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
          .font(.system(size: 18))
          .frame(width: 22, height: 22)
      }
      
      TextField(
        allDirectoriesDisabled
        ? "All directories disabled"
        : "Search \(enabledFileCount) files...",
        text: $viewModel.query
      )
      .focused(isSearchFieldFocused)
      .textFieldStyle(.plain)
      .font(.system(size: 18))
      .onSubmit { onSubmit() }
      .disabled(allDirectoriesDisabled)
      
      if viewModel.state == .searching {
        SpinnerView()
          .transition(.identity)
      }
      
      HStack(spacing: 6) {
        if !directoryStore.directories.isEmpty {
          DirectoryScopeButton(scope: $viewModel.filters.directoryScope)
        }
        
        if !viewModel.availableFileTypes.isEmpty {
          SearchFilterButton(
            selectedTypes: $viewModel.filters.fileTypes,
            availableTypes: viewModel.availableFileTypes
          )
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .task {
      await updateFileCount()
      await viewModel.loadAvailableFileTypes()
    }
    .onChange(of: directoryStore.directories) {
      Task {
        await updateFileCount()
        await viewModel.loadAvailableFileTypes()
      }
    }
    .onChange(of: viewModel.filters.directoryScope) {
      Task { await updateFileCount() }
    }
    .onChange(of: viewModel.filters) {
      viewModel.filtersChanged()
    }
  }
  
  private func updateFileCount() async {
    let scope = viewModel.filters.directoryScope
    enabledFileCount =
    (try? await AppDatabase.shared.fetchEnabledFileCount(scopePath: scope))
    ?? 0
  }
}
