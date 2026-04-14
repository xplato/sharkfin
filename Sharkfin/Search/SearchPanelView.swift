import SwiftUI

struct SearchPanelView: View {
  @Bindable var viewModel: SearchViewModel
  @Environment(SearchController.self) private var searchController
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var isSearchFieldFocused: Bool
  @Namespace private var glassNamespace
  
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void
  
  private static let outerCornerRadius: CGFloat = 24
  private static let innerCornerRadius: CGFloat = SearchPanel.cornerRadius
  private static let outerPadding: CGFloat = 12
  
  private var innerSolidBackground: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Self.innerCornerRadius)
        .fill(colorScheme == .dark ? Color(white: 0.28) : Color(nsColor: .windowBackgroundColor))
      RoundedRectangle(cornerRadius: Self.innerCornerRadius)
        .stroke(.primary.opacity(colorScheme == .dark ? 0.3 : 0.2), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
  }
  
  var body: some View {
    GlassEffectContainer(spacing: 16) {
      VStack(spacing: 16) {
        GlassWrapper(id: "search", namespace: glassNamespace) {
          SearchBarView(
            viewModel: viewModel,
            onSubmit: { viewModel.submitSearch() },
            onDismiss: { onDismiss() },
            onOpenSettings: { onOpenSettings() },
            isSearchFieldFocused: $isSearchFieldFocused
          )
          .background { innerSolidBackground }
          .clipShape(.rect(cornerRadius: Self.innerCornerRadius))
        }
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

        if !viewModel.results.isEmpty {
          GlassWrapper(id: "results", namespace: glassNamespace) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { innerSolidBackground }
            .clipShape(.rect(cornerRadius: Self.innerCornerRadius))
          }
          .frame(maxHeight: .infinity)
          .transition(
            .asymmetric(
              insertion: .scale(scale: 0.98, anchor: .top)
                .combined(with: .opacity),
              removal: .scale(scale: 0.98, anchor: .top)
                .combined(with: .opacity)
            )
          )
        } else if viewModel.state == .noResults {
          GlassWrapper(id: "no-results", namespace: glassNamespace) {
            noResultsView
              .background { innerSolidBackground }
              .clipShape(.rect(cornerRadius: Self.innerCornerRadius))
          }
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
      .padding(32)
      .frame(width: SearchPanel.panelWidth)
      .frame(maxHeight: .infinity, alignment: .top)
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

struct GlassWrapper<Content: View>: View {
  let id: String
  let namespace: Namespace.ID

  let content: Content

  @Environment(\.colorScheme) private var colorScheme

  private static var outerCornerRadius: CGFloat { 24 }
  private static var innerCornerRadius: CGFloat { SearchPanel.cornerRadius }
  private static var outerPadding: CGFloat { 12 }

  init(id: String, namespace: Namespace.ID, @ViewBuilder content: () -> Content) {
    self.id = id
    self.namespace = namespace
    self.content = content()
  }
  
  var body: some View {
    VStack {
      content
    }
    .padding(Self.outerPadding)
    .glassEffect(.clear, in: .rect(cornerRadius: Self.outerCornerRadius))
    .glassEffectID(self.id, in: self.namespace)
    .background(
      colorScheme == .dark ? .black.opacity(0.5) : .black.opacity(0.1),
      in: .rect(cornerRadius: Self.outerCornerRadius)
    )
    .shadow(color: .black.opacity(0.125), radius: 12, y: 6)
  }
}

