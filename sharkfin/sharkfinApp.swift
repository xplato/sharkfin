import SwiftUI
import KeyboardShortcuts

@main
struct sharkfinApp: App {
  @State private var directoryStore = DirectoryStore(database: .shared)
  @State private var modelManager = CLIPModelManager()
  @State private var appState = AppState()

  var body: some Scene {
    MenuBarExtra("Sharkfin", systemImage: "magnifyingglass") {
      MenuBarContent(appState: appState)
    }

    Window("Sharkfin Settings", id: "settings") {
      SettingsView()
        .environment(directoryStore)
        .environment(modelManager)
    }
    .defaultSize(width: 800, height: 500)
    .windowResizability(.contentSize)
  }
}

@MainActor
@Observable
final class AppState {
  private var searchPanel: SearchPanel?
  private var searchViewModel = SearchViewModel()
  private var resignKeyObserver: Any?

  init() {
    KeyboardShortcuts.onKeyUp(for: .activateSearch) { [self] in
      activateSearch()
    }

    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: .searchPanelDidResignKey,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.hideSearch()
      }
    }
  }

  func activateSearch() {
    if let panel = searchPanel, panel.isVisible {
      hideSearch()
    } else {
      showSearch()
    }
  }

  private func showSearch() {
    let panel = getOrCreatePanel()

    // Center horizontally on screen, upper third vertically
    if let screen = NSScreen.screens.first(where: {
      $0.frame.contains(NSEvent.mouseLocation)
    }) ?? NSScreen.main ?? NSScreen.screens.first {
      let screenFrame = screen.visibleFrame
      let panelWidth: CGFloat = 680
      let panelHeight: CGFloat = 400
      let x = screenFrame.midX - panelWidth / 2
      // Top edge of panel at ~72% up the screen, matching Spotlight placement
      let panelTopY = screenFrame.origin.y + screenFrame.height * 0.72
      let y = panelTopY - panelHeight
      panel.setFrame(
        NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
        display: false
      )
    }

    searchViewModel.clearSearch()
    panel.makeKeyAndOrderFront(nil)

    // Focus the text field after the hosting view has laid out
    DispatchQueue.main.async {
      if let textField = self.findTextField(in: panel.contentView) {
        panel.makeFirstResponder(textField)
      }
    }
  }

  private func hideSearch() {
    searchPanel?.orderOut(nil)
  }

  private func getOrCreatePanel() -> SearchPanel {
    if let existing = searchPanel { return existing }

    let panel = SearchPanel(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 400)
    )

    let hostingView = NSHostingView(
      rootView: SearchPanelView(
        viewModel: searchViewModel,
        onDismiss: { [weak self] in
          self?.hideSearch()
        },
        onOpenSettings: { [weak self] in
          self?.hideSearch()
          NSApplication.shared.activate(ignoringOtherApps: true)
          if let settingsWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("settings") == true
          }) {
            settingsWindow.makeKeyAndOrderFront(nil)
          }
        }
      )
    )

    panel.contentView = hostingView

    // Round the corners at the AppKit layer level so the
    // window frame itself is clipped, not just the SwiftUI content.
    hostingView.wantsLayer = true
    hostingView.layer?.cornerRadius = 12
    hostingView.layer?.cornerCurve = .continuous
    hostingView.layer?.masksToBounds = true
    self.searchPanel = panel
    return panel
  }

  private func findTextField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let textField = view as? NSTextField, textField.isEditable {
      return textField
    }
    for subview in view.subviews {
      if let found = findTextField(in: subview) {
        return found
      }
    }
    return nil
  }
}

struct MenuBarContent: View {
  @Environment(\.openWindow) private var openWindow
  let appState: AppState

  var body: some View {
    Button("Open Search") {
      appState.activateSearch()
    }
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
