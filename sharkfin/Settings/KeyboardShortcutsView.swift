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
    .frame(minWidth: 350, idealWidth: 800, maxWidth: 1200,
           minHeight: 150, idealHeight: 500, maxHeight: 900)
  }
}
