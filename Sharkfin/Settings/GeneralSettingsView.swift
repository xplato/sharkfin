import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
  @Environment(DirectoryStore.self) private var directoryStore
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  @AppStorage("preserveSearchFilter") private var preserveSearchFilter = false
  @AppStorage("searchResultColumns") private var searchResultColumns = 4

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
        Toggle(isOn: $preserveSearchFilter) {
          Text("Preserve search filters")
          Text(
            preserveSearchFilter
              ? "Search filters will not be cleared automatically."
              : "Search filters will be cleared 15 seconds after closing the searchbar."
          )
        }

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
