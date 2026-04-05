import SwiftUI

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @AppStorage("watchDirectories") private var watchDirectories = false

  var body: some View {
    Form {
      Section("Features") {
        Toggle("Watch for changes", isOn: $watchDirectories)
      }
      
      Section("Models") {
        ForEach(CLIPModelSpec.all) { model in
          ModelRowView(model: model)
        }
      }

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
