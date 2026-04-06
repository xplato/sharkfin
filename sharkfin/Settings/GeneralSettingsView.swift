import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @AppStorage("watchDirectories") private var watchDirectories = false
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  
  var body: some View {
    Form {
      Section("Features") {
        Toggle("Start at login", isOn: $startAtLogin)
          .onChange(of: startAtLogin) { _, newValue in
            do {
              if newValue {
                try SMAppService.mainApp.register()
              } else {
                try SMAppService.mainApp.unregister()
              }
            } catch {
              // Revert the toggle if the operation fails
              startAtLogin = SMAppService.mainApp.status == .enabled
            }
          }
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
