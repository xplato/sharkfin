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
      let y = screenFrame.maxY - panelHeight - (screenFrame.height * 0.15)
      panel.setFrame(
        NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
        display: false
      )
    }

    searchViewModel.clearSearch()
    panel.makeKeyAndOrderFront(nil)

    DispatchQueue.main.async {
      panel.makeKey()
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
    self.searchPanel = panel

    searchViewModel.onStateChange = { [weak self] in
      self?.updatePanelSize()
    }

    return panel
  }

  private func updatePanelSize() {
    guard let panel = searchPanel,
          let hostingView = panel.contentView as? NSHostingView<SearchPanelView>
    else { return }

    let fittingSize = hostingView.fittingSize
    let newFrame = NSRect(
      x: panel.frame.origin.x,
      y: panel.frame.maxY - fittingSize.height,
      width: panel.frame.width,
      height: fittingSize.height
    )
    panel.setFrame(newFrame, display: true, animate: true)
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
