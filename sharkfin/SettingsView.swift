import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
  var body: some View {
    Form {
      Section("Keyboard Shortcut") {
        KeyboardShortcuts.Recorder("Activate Search:", name: .activateSearch)
      }
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 200)
  }
}
