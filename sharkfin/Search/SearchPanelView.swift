import SwiftUI

struct SearchPanelView: View {
  @Bindable var viewModel: SearchViewModel
  @Environment(SearchController.self) private var searchController
  var onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Content card — top-aligned so it grows downward
      VStack(spacing: 0) {
        SearchBarView(
          viewModel: viewModel,
          onSubmit: { viewModel.submitSearch() },
          onDismiss: { onDismiss() }
        )

        if searchController.selectedResult != nil {
          Divider()
          selectedDetailView
        } else if !viewModel.results.isEmpty {
          Divider()
          SearchResultsGridView(results: viewModel.results)
            .frame(maxHeight: 700)
        } else if viewModel.state == .noResults {
          Divider()
          noResultsView
        }
      }
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(.separator, lineWidth: 1)
      }
      .animation(.easeInOut(duration: 0.2), value: viewModel.state)
      .animation(.easeInOut(duration: 0.2), value: searchController.selectedResult?.id)

      Spacer(minLength: 0)
    }
    .frame(width: 680)
    .onChange(of: viewModel.query) {
      if searchController.selectedResult != nil {
        searchController.clearSelection()
      }
      viewModel.queryChanged()
    }
    .onKeyPress(.escape) {
      handleEscape()
      return .handled
    }
    .onKeyPress(phases: .down) { keyPress in
      if keyPress.key == "," && keyPress.modifiers == .command {
        onDismiss()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        return .handled
      }
      return .ignored
    }
  }

  // MARK: - Detail View (placeholder)

  @ViewBuilder
  private var selectedDetailView: some View {
    if let result = searchController.selectedResult {
      VStack(spacing: 8) {
        if let thumbPath = result.thumbnailPath,
           let nsImage = NSImage(contentsOfFile: thumbPath) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        Text(result.filename)
          .font(.headline)
        Text(result.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity)
      .padding()
      .frame(maxHeight: 700)
    }
  }

  private var noResultsView: some View {
    VStack(spacing: 12) {
      Text("No relevant results were found.")
        .foregroundStyle(.secondary)
      Button("Clear search") {
        viewModel.clearSearch()
      }
      .buttonStyle(.bordered)
    }
    .frame(height: 100)
    .frame(maxWidth: .infinity)
  }

  // MARK: - Navigation

  private func handleEscape() {
    if searchController.selectedResult != nil {
      searchController.clearSelection()
    } else if viewModel.state != .idle {
      viewModel.clearSearch()
    } else {
      onDismiss()
    }
  }
}
