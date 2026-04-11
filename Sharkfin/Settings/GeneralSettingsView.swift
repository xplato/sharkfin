import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  @AppStorage(StorageKey.searchResultColumns) private var searchResultColumns =
  4
  
  var body: some View {
    Form {
      Section("Functionality") {
        KeyboardShortcuts.Recorder("Show searchbar", name: .activateSearch)
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
      
      Section("Search") {
        Picker("Result columns", selection: $searchResultColumns) {
          Text("3").tag(3)
          Text("4").tag(4)
          Text("5").tag(5)
        }
      }
      
      Section(
        header: Text("Directories"),
        footer: Text(
          "After indexing, the contents of these directories will be included in search results."
        )
      ) {
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
      
      Section(
        header: Text("Models"),
        footer: Text(
          "Models are downloaded from [huggingface.co/xplato](https://huggingface.co/xplato)"
        )
      ) {
        ForEach(CLIPModelPackage.all) { package in
          ModelPackageRowView(package: package)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      // Prevent the keyboard shortcut recorder from receiving
      // focus when the settings window first opens.
      DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
      }
    }
  }
}
