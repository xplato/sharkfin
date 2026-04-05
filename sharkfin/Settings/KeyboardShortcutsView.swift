import SwiftUI
import KeyboardShortcuts

struct KeyboardShortcutsView: View {
  var body: some View {
    Form {
      Section("Keyboard Shortcut") {
        KeyboardShortcuts.Recorder("Activate Search:", name: .activateSearch)
      }
    }
    .formStyle(.grouped)
  }
}
