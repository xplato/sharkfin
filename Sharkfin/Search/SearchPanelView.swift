import SwiftUI

struct SearchPanelView: View {
  @Bindable var viewModel: SearchViewModel
  @Environment(SearchController.self) private var searchController
  @FocusState private var isSearchFieldFocused: Bool
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      // Content card — top-aligned so it grows downward
      VStack(spacing: 0) {
        SearchBarView(
          viewModel: viewModel,
          onSubmit: { viewModel.submitSearch() },
          onDismiss: { onDismiss() },
          onOpenSettings: { onOpenSettings() },
          isSearchFieldFocused: $isSearchFieldFocused
        )
        
        if !viewModel.results.isEmpty {
          Divider()
          ZStack {
            SearchResultsGridView(
              results: viewModel.displayedResults,
              hasMore: viewModel.hasMoreResults,
              scrollToTopToken: viewModel.query,
              onShowMore: { viewModel.showMoreResults() }
            )
            .opacity(searchController.selectedResult == nil ? 1 : 0)
            .allowsHitTesting(searchController.selectedResult == nil)
            
            if let selected = searchController.selectedResult {
              SearchResultDetailView(result: selected)
            }
          }
          .frame(maxHeight: 700)
        } else if viewModel.state == .noResults {
          Divider()
          noResultsView
        }
      }
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: SearchPanel.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: SearchPanel.cornerRadius)
          .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
      }
      .animation(.easeInOut(duration: 0.2), value: viewModel.state)
      .animation(
        .easeInOut(duration: 0.2),
        value: searchController.selectedResult?.id
      )
      
      Spacer(minLength: 0)
    }
    .frame(width: SearchPanel.panelWidth)
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
        onOpenSettings()
        return .handled
      }
      return .ignored
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
      isSearchFieldFocused = true
    } else if viewModel.state != .idle {
      viewModel.clearSearch()
    } else {
      onDismiss()
    }
  }
}
