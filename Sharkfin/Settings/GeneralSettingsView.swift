import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  @State private var isEditingShortcut = false
  @AppStorage(StorageKey.searchResultColumns) private var searchResultColumns =
  4
  
  var body: some View {
    Form {
      Section("Functionality") {
        LabeledContent("Show searchbar") {
          if isEditingShortcut {
            HStack(spacing: 8) {
              KeyboardShortcuts.Recorder(for: .activateSearch) { _ in
                isEditingShortcut = false
              }
              Button("Cancel") {
                isEditingShortcut = false
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
            }
          } else {
            HStack(spacing: 8) {
              if let shortcut = KeyboardShortcuts.getShortcut(for: .activateSearch) {
                Text(shortcut.description)
                  .foregroundStyle(.secondary)
              } else {
                Text("None")
                  .foregroundStyle(.tertiary)
              }
              Button("Change") {
                isEditingShortcut = true
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
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
        ForEach(CLIPModelSpec.all) { model in
          ModelRowView(model: model)
        }
      }
    }
    .formStyle(.grouped)
  }
}
