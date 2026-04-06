import KeyboardShortcuts
import SwiftUI

struct KeyboardShortcutsView: View {
  var body: some View {
    Form {
      Section("Keyboard Shortcut") {
        KeyboardShortcuts.Recorder("Show searchbar", name: .activateSearch)
      }
    }
    .formStyle(.grouped)
  }
}
