import SwiftUI

struct SearchPanelView: View {
  @Bindable var viewModel: SearchViewModel
  var onDismiss: () -> Void
  var onOpenSettings: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Content card — top-aligned so it grows downward
      VStack(spacing: 0) {
        SearchBarView(
          viewModel: viewModel,
          onSubmit: { viewModel.performSearch() },
          onSettingsTapped: { onOpenSettings() }
        )

        if viewModel.state != .idle {
          Divider()

          Group {
            switch viewModel.state {
            case .searching:
              VStack(spacing: 12) {
                ProgressView()
                Text("Searching...")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .frame(height: 120)
              .frame(maxWidth: .infinity)

            case .results:
              SearchResultsGridView(
                results: viewModel.results,
                onResultTapped: { result in
                  NSWorkspace.shared.selectFile(
                    result.path,
                    inFileViewerRootedAtPath: ""
                  )
                }
              )
              .frame(maxHeight: 280)

            case .noResults:
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

            case .idle:
              EmptyView()
            }
          }
          .transition(.opacity)
        }
      }
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(.separator, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
      .animation(.easeInOut(duration: 0.2), value: viewModel.state)

      Spacer(minLength: 0)
    }
    .frame(width: 680)
    .onKeyPress(.escape) {
      handleEscape()
      return .handled
    }
  }

  private func handleEscape() {
    if viewModel.state != .idle {
      viewModel.clearSearch()
    } else {
      onDismiss()
    }
  }
}
