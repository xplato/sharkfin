import SwiftUI

struct AdvancedSettingsView: View {
  /// All `@AppStorage` keys used for dialog suppression toggles.
  /// Add new keys here as more "Don't show again" dialogs are introduced.
  private static let suppressionKeys = [
    "suppressDisableDirectoryWarning",
  ]

  @State private var showResetConfirmation = false

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

      Section("Warnings") {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Reset All Warnings")
            Text("Show confirmation dialogs that were previously dismissed with \"Don't show again.\"")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Reset") {
            showResetConfirmation = true
          }
          .alert("Reset All Warnings?", isPresented: $showResetConfirmation) {
            Button("Reset") {
              for key in Self.suppressionKeys {
                UserDefaults.standard.removeObject(forKey: key)
              }
            }
            Button("Cancel", role: .cancel) { }
          } message: {
            Text("All previously suppressed confirmation dialogs will be shown again.")
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}
