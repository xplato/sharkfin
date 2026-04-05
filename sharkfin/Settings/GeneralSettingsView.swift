import SwiftUI

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @AppStorage("watchDirectories") private var watchDirectories = false
  
  var body: some View {
    Form {
      Section("Features") {
        Toggle("Watch for changes", isOn: $watchDirectories)
      }
      
      Section(header: Text("Directories"), footer: Text("After indexing, the contents of these directories will be included in search results.")) {
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
      
      Section("Models") {
        ForEach(CLIPModelSpec.all) { model in
          ModelRowView(model: model)
        }
      }
    }
    .formStyle(.grouped)
  }
}
