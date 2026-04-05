import SwiftUI

struct AdvancedSettingsView: View {
  var body: some View {
    Form {
      Section("Database") {
        Label("Database is accessible", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    }
    .formStyle(.grouped)
  }
}
