import SwiftUI

struct DirectoryRowView: View {
  let directory: SharkfinDirectory
  @Environment(DirectoryStore.self) private var store
  @Environment(IndexingService.self) private var indexingService
  @State private var showDeleteConfirmation = false
  @State private var showDisableConfirmation = false
  @AppStorage("suppressDisableDirectoryWarning") private var suppressDisableWarning = false

  /// Shorten the path for display: /Users/tristan/.../DirName
  private var shortenedPath: String {
    let path = directory.path
    let components = path.split(separator: "/")
    guard components.count > 3 else { return path }
    return "/\(components[0])/\(components[1])/\u{2026}/\(components.last ?? "")"
  }

  private var progress: IndexingProgress? {
    guard let id = directory.id else { return nil }
    return indexingService.progressByDirectory[id]
  }

  private var isIndexing: Bool {
    guard let id = directory.id else { return false }
    return indexingService.isIndexing(id)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: "folder.fill")
        .foregroundStyle(.secondary)
        .font(.title3)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(directory.label ?? URL(fileURLWithPath: directory.path).lastPathComponent)
            .fontWeight(.medium)
          Text("(\(shortenedPath))")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        if let progress {
          progressView(progress)
        } else if directory.lastIndexedAt == nil {
          notIndexedView
        }
      }

      Spacer()

      if isIndexing {
        Button {
          guard let id = directory.id else { return }
          indexingService.cancelIndexing(id)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .buttonStyle(.borderless)
        .help("Cancel indexing")
      } else {
        Button {
          indexingService.indexDirectory(directory)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(!indexingService.modelsReady)
        .help(indexingService.modelsReady ? "Index now" : "Download vision model first")
      }

      Toggle("Enabled", isOn: Binding(
        get: { directory.enabled },
        set: { newValue in
          guard let id = directory.id else { return }
          if !newValue && !suppressDisableWarning {
            showDisableConfirmation = true
          } else {
            try? store.database.updateDirectoryEnabled(id: id, enabled: newValue)
          }
        }
      ))
      .toggleStyle(.switch)
      .labelsHidden()

      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .confirmationDialog(
        "Remove \"\(directory.label ?? directory.path)\"?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) {
          guard let id = directory.id else { return }
          try? store.database.deleteDirectory(id: id)
        }
      } message: {
        Text("This directory will be removed from Sharkfin. New indexing will not be performed, and existing analysis, thumbnails, and references will be deleted. The contents of the directory will remain unchanged.")
      }
    }
    .padding(.vertical, 6)
    .alert(
      "Disable \"\(directory.label ?? URL(fileURLWithPath: directory.path).lastPathComponent)\"?",
      isPresented: $showDisableConfirmation
    ) {
      Button("Disable") {
        guard let id = directory.id else { return }
        try? store.database.updateDirectoryEnabled(id: id, enabled: false)
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Search results from this directory will be hidden while it is disabled.")
    }
    .dialogSuppressionToggle(isSuppressed: $suppressDisableWarning)
  }

  private var notIndexedView: some View {
    Text("Not yet indexed — click \(Image(systemName: "arrow.clockwise")) to start")
      .font(.caption)
      .foregroundStyle(.orange)
      .onTapGesture {
        if indexingService.modelsReady {
          indexingService.indexDirectory(directory)
        }
      }
  }

  @ViewBuilder
  private func progressView(_ progress: IndexingProgress) -> some View {
    switch progress.phase {
    case .scanning:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.small)
        Text("Scanning files...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .indexing:
      VStack(alignment: .leading, spacing: 2) {
        ProgressView(
          value: Double(progress.processed),
          total: Double(max(progress.total, 1))
        )
        .controlSize(.small)
        Text("\(progress.processed) of \(progress.total) files indexed")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .complete(let count):
      Text("Indexed \(count) files")
        .font(.caption)
        .foregroundStyle(.green)
    case .upToDate:
      Text("Up to date")
        .font(.caption)
        .foregroundStyle(.green)
    case .error(let message):
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
    case .cancelled:
      Text("Cancelled")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
