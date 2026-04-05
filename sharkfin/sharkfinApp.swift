import SwiftUI

@main
struct sharkfinApp: App {
    var body: some Scene {
        MenuBarExtra("Sharkfin", systemImage: "magnifyingglass") {
            MenuBarContent()
        }

        Window("Sharkfin Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 600, height: 400)
        .windowResizability(.contentSize)
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
