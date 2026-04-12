import SwiftUI

struct SearchPanelView: View {
  @Bindable var viewModel: SearchViewModel
  @Environment(SearchController.self) private var searchController
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var isSearchFieldFocused: Bool
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void
  
  private var glassBackground: some View {
    Color.clear
      .glassEffect(
        .regular.tint(.primary.opacity(0.075)),
        in: .rect(cornerRadius: SearchPanel.cornerRadius)
      )
      .id(colorScheme)
  }
  
  var body: some View {
    VStack(spacing: 12) {
      // Search bar — its own glass block
      SearchBarView(
        viewModel: viewModel,
        onSubmit: { viewModel.submitSearch() },
        onDismiss: { onDismiss() },
        onOpenSettings: { onOpenSettings() },
        isSearchFieldFocused: $isSearchFieldFocused
      )
      .clipShape(.rect(cornerRadius: SearchPanel.cornerRadius))
      .background { glassBackground }
      
      // Results — separate glass block below
      if !viewModel.results.isEmpty {
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
        .frame(maxHeight: 732)
        .clipShape(.rect(cornerRadius: SearchPanel.cornerRadius))
        .background { glassBackground }
        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
      } else if viewModel.state == .noResults {
        noResultsView
          .clipShape(.rect(cornerRadius: SearchPanel.cornerRadius))
          .background { glassBackground }
          .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
      }
      
      Spacer(minLength: 0)
    }
    .animation(.easeInOut(duration: 0.2), value: viewModel.state)
    .animation(
      .easeInOut(duration: 0.2),
      value: searchController.selectedResult?.id
    )
    .padding(32)
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

