import SwiftUI

struct AdvancedSettingsView: View {
  var body: some View {
    Form {
      Section("Database") {
        Label("Local database initialized", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }

      Section("Storage") {
        HStack {
          Text(AppDatabase.dataDirectoryURL.path(percentEncoded: false))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

          Spacer()

          Button("Open in Finder") {
            NSWorkspace.shared.open(AppDatabase.dataDirectoryURL)
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}
