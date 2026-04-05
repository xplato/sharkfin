import SwiftUI

struct DirectoryRowView: View {
  let directory: SharkfinDirectory
  @Environment(DirectoryStore.self) private var store
  @State private var showDeleteConfirmation = false

  /// Shorten the path for display: /Users/tristan/.../DirName
  private var shortenedPath: String {
    let path = directory.path
    let components = path.split(separator: "/")
    guard components.count > 3 else { return path }
    return "/\(components[0])/\(components[1])/\u{2026}/\(components.last ?? "")"
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
      }

      Spacer()

      Toggle("Enabled", isOn: Binding(
        get: { directory.enabled },
        set: { newValue in
          guard let id = directory.id else { return }
          try? store.database.updateDirectoryEnabled(id: id, enabled: newValue)
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
        Text("This directory will be removed from Sharkfin. New indexing will not be performed, and existing analysis, thumbnails, and references will be deleted. The content of the directory will remain unchanged.")
      }
    }
    .padding(.vertical, 6)
  }
}
