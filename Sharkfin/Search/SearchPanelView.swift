import SwiftUI

struct SearchPanelView: View {
  @Bindable var viewModel: SearchViewModel
  @Environment(SearchController.self) private var searchController
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var isSearchFieldFocused: Bool
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void
  
  private static let outerCornerRadius: CGFloat = 24
  private static let innerCornerRadius: CGFloat = SearchPanel.cornerRadius
  private static let outerPadding: CGFloat = 12
  
  private var outerGlassBackground: some View {
    Color.clear
      .glassEffect(
        .clear,
        in: .rect(cornerRadius: Self.outerCornerRadius)
      )
      .background(colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.1))
      .clipShape(.rect(cornerRadius: Self.outerCornerRadius))
      .id(colorScheme)
  }
  
  private var innerSolidBackground: some View {
    RoundedRectangle(cornerRadius: Self.innerCornerRadius)
      .fill(.background)
      .stroke(.primary.opacity(0.2), lineWidth: 1)
      .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
  }
  
  private var innerBlurBackground: some View {
    RoundedRectangle(cornerRadius: Self.innerCornerRadius)
      .fill(colorScheme == .dark ? .black.opacity(0.025) : .white.opacity(0.05))
      .stroke(.primary.opacity(0.2), lineWidth: 1)
      .background(.regularMaterial)
  }
  
  var body: some View {
    VStack(spacing: 0) {
      // Single outer glass container for search bar + results
      VStack(spacing: 8) {
        SearchBarView(
          viewModel: viewModel,
          onSubmit: { viewModel.submitSearch() },
          onDismiss: { onDismiss() },
          onOpenSettings: { onOpenSettings() },
          isSearchFieldFocused: $isSearchFieldFocused
        )
        .background { innerSolidBackground }
        .clipShape(.rect(cornerRadius: Self.innerCornerRadius))
        
        
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
          .frame(maxHeight: .infinity)
          .background(.background.opacity(0.25))
          .background { innerBlurBackground }
          .clipShape(.rect(cornerRadius: Self.innerCornerRadius))
          .transition(
            .asymmetric(
              insertion: .scale(scale: 0.98, anchor: .top)
                .combined(with: .opacity),
              removal: .scale(scale: 0.98, anchor: .top)
                .combined(with: .opacity)
            )
          )
        } else if viewModel.state == .noResults {
          noResultsView
            .background { innerBlurBackground }
            .clipShape(.rect(cornerRadius: Self.innerCornerRadius))
            .transition(
              .asymmetric(
                insertion: .scale(scale: 0.85, anchor: .top)
                  .combined(with: .opacity)
                  .combined(with: .offset(y: -8)),
                removal: .scale(scale: 0.95, anchor: .top)
                  .combined(with: .opacity)
              )
            )
        }
      }
      .padding(Self.outerPadding)
      .background { outerGlassBackground }
      .clipShape(.rect(cornerRadius: Self.outerCornerRadius))
      .shadow(color: .black.opacity(0.125), radius: 12, y: 6)
      
      Spacer(minLength: 0)
    }
    .animation(.spring(duration: 0.35, bounce: 0.2), value: viewModel.state)
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

