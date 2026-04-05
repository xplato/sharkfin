import SwiftUI
import KeyboardShortcuts

@main
struct sharkfinApp: App {
  var body: some Scene {
    MenuBarExtra("Sharkfin", systemImage: "magnifyingglass") {
      MenuBarContent()
    }
    
    Window("Sharkfin Settings", id: "settings") {
      SettingsView()
    }
    .defaultSize(width: 800, height: 500)
    .windowResizability(.contentSize)
  }
}

@MainActor
@Observable
final class AppState {
  init() {
    KeyboardShortcuts.onKeyUp(for: .activateSearch) { [self] in
      activateSearch()
    }
  }
  
  func activateSearch() {
    // TODO: Open the floating search panel
  }
}

struct MenuBarContent: View {
  @Environment(\.openWindow) private var openWindow
  
  var body: some View {
    Button("Open Search") {}
      .keyboardShortcut("F")
    
    Button("Settings...") {
      NSApplication.shared.activate(ignoringOtherApps: true)
      openWindow(id: "settings")
    }
    .keyboardShortcut(",")
    
    Divider()
    
    Button("Quit") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("Q")
  }
}
