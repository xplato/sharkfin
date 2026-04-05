import SwiftUI

struct AddDirectoryButton: View {
  @Environment(DirectoryStore.self) private var store

  var body: some View {
    Button {
      selectDirectory()
    } label: {
      Label("Add Directory", systemImage: "plus")
    }
  }

  private func selectDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Select a directory to index"
    panel.prompt = "Add"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      var directory = SharkfinDirectory(
        path: url.path(percentEncoded: false),
        label: url.lastPathComponent,
        watch: false,
        addedAt: Date(),
        bookmark: bookmarkData
      )

      try store.database.addDirectory(&directory)
    } catch {
      print("Failed to add directory: \(error)")
    }
  }
}
