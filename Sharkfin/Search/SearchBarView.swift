import SwiftUI
internal import Combine

private struct SearchIconView: View {
  var isAnimating: Bool
  @State private var rotation: Double = -10
  @State private var dimmed = false
  
  var body: some View {
    Image(systemName: "magnifyingglass")
      .foregroundStyle(isAnimating ? .primary : .secondary)
      .font(.system(size: 18))
      .frame(width: 22, height: 22)
      .opacity(dimmed ? 0.4 : 1.0)
      .rotationEffect(
        .degrees(rotation),
        anchor: UnitPoint(x: 0.43, y: 0.43)
      )
      .animation(
        isAnimating
        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        : .default,
        value: rotation
      )
      .animation(
        isAnimating
        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        : .default,
        value: dimmed
      )
      .onChange(of: isAnimating, initial: true) {
        rotation = isAnimating ? 10 : 0
        dimmed = isAnimating
      }
  }
}

struct SearchBarView: View {
  @Bindable var viewModel: SearchViewModel
  var onSubmit: () -> Void
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void
  var isSearchFieldFocused: FocusState<Bool>.Binding
  
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(CLIPModelManager.self) private var modelManager
  @Environment(IndexingService.self) private var indexingService
  @Environment(SearchController.self) private var searchController
  @State private var enabledFileCount: Int = 0
  
  /// Tracks only phase changes (not per-file progress ticks) to avoid
  /// triggering multiple updates per frame during indexing.
  private var indexingPhases: [Int64: IndexingPhase] {
    indexingService.progressByDirectory.mapValues(\.phase)
  }
  
  private var needsSetup: Bool {
    !modelManager.isReady || directoryStore.directories.isEmpty
  }
  
  private var allDirectoriesDisabled: Bool {
    !directoryStore.directories.isEmpty
    && !directoryStore.directories.contains(where: \.enabled)
  }
  
  private var isDisabled: Bool {
    needsSetup || allDirectoriesDisabled
  }
  
  private var placeholderText: String {
    if needsSetup {
      return "Setup required"
    } else if allDirectoriesDisabled {
      return "All directories disabled"
    } else {
      return "Search \(enabledFileCount.formatted(.number)) files..."
    }
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
      } else if isDisabled {
        Button {
          onOpenSettings()
        } label: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .font(.system(size: 18))
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(needsSetup ? "Setup required. Click to open settings." : "All directories are disabled. Click to open settings.")
      } else {
        SearchIconView(isAnimating: viewModel.state == .searching)
      }
      
      TextField(
        placeholderText,
        text: $viewModel.query
      )
      .focused(isSearchFieldFocused)
      .textFieldStyle(.plain)
      .font(.system(size: 18))
      .onSubmit { onSubmit() }
      .disabled(isDisabled)
      
      HStack(spacing: 6) {
        if isDisabled {
          Button {
            onOpenSettings()
          } label: {
            FilterButtonLabel(text: "Open Settings", isActive: false)
          }
          .buttonStyle(.plain)
          .fixedSize()
        } else {
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
    .onChange(of: indexingPhases) {
      Task {
        await updateFileCount()
        await viewModel.loadAvailableFileTypes()
      }
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
