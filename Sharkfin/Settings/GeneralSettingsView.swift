import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(DirectoryWatcherService.self) private var directoryWatcher
  @AppStorage("watchDirectories") private var watchDirectories = true
  @AppStorage("indexOnLaunch") private var indexOnLaunch = true
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  
  var body: some View {
    Form {
      Section("Functionality") {
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
      }
      
      Section("Automatic Indexing") {
        Toggle(isOn: $watchDirectories) {
          Text("Watch for changes")
          Text("Automatically index enabled directories after file system changes.")
        }
        .onChange(of: watchDirectories) { _, _ in
          directoryWatcher.restartIfNeeded()
        }
        Toggle(isOn: $indexOnLaunch) {
          Text("Index on launch")
          Text("Automatically index enabled directories when Sharkfin launches.")
        }
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
      
      Section(header: Text("Models"), footer: Text("Models are downloaded from [huggingface.co/xplato](https://huggingface.co/xplato)")) {
        ForEach(CLIPModelSpec.all) { model in
          ModelRowView(model: model)
        }
      }
    }
    .formStyle(.grouped)
  }
}
