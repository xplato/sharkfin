import SwiftUI

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore

  var body: some View {
    Form {
      Section("Indexed Directories") {
        if directoryStore.directories.isEmpty {
          Text("No directories added yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(directoryStore.directories) { directory in
            DirectoryRowView(directory: directory)
          }
        }

        AddDirectoryButton()
      }
    }
    .formStyle(.grouped)
  }
}
