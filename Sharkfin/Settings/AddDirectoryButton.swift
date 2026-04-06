import AppKit
import SwiftUI

struct AddDirectoryButton: View {
  @Environment(DirectoryStore.self) private var store
  @Environment(IndexingService.self) private var indexingService

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

    // Accessory checkbox for immediate indexing
    let checkbox = NSButton(
      checkboxWithTitle: "Index immediately once added",
      target: nil,
      action: nil
    )
    checkbox.state = .on
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
    checkbox.frame.origin = NSPoint(x: 4, y: 4)
    checkbox.sizeToFit()
    container.addSubview(checkbox)
    panel.accessoryView = container

    guard panel.runModal() == .OK, let url = panel.url else { return }

    let shouldIndex = checkbox.state == .on

    do {
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      var directory = SharkfinDirectory(
        path: url.path(percentEncoded: false),
        label: url.lastPathComponent,
        enabled: true,
        addedAt: Date(),
        bookmark: bookmarkData
      )

      try store.database.addDirectory(&directory)

      if shouldIndex, indexingService.modelsReady {
        indexingService.indexDirectory(directory)
      }
    } catch {
      print("Failed to add directory: \(error)")
    }
  }
}
