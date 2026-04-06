import SwiftUI
import KeyboardShortcuts
import Quartz

@main
struct sharkfinApp: App {
  @State private var directoryStore: DirectoryStore
  @State private var modelManager: CLIPModelManager
  @State private var indexingService: IndexingService
  @State private var appState: AppState

  init() {
    let manager = CLIPModelManager()
    _modelManager = State(initialValue: manager)
    _indexingService = State(initialValue: IndexingService(
      database: .shared, modelManager: manager
    ))
    let store = DirectoryStore(database: .shared)
    _directoryStore = State(initialValue: store)
    _appState = State(initialValue: AppState(
      database: .shared, modelManager: manager, directoryStore: store
    ))
  }

  var body: some Scene {
    MenuBarExtra("Sharkfin", systemImage: "magnifyingglass") {
      MenuBarContent(appState: appState)
    }

    Settings {
      SettingsView()
        .environment(directoryStore)
        .environment(modelManager)
        .environment(indexingService)
    }
  }
}

@MainActor
@Observable
final class AppState {
  private var searchPanel: SearchPanel?
  private var searchViewModel: SearchViewModel
  private var searchController = SearchController()
  let directoryStore: DirectoryStore
  private var resignKeyObserver: Any?
  private var settingsOpener: (() -> Void)?

  init(database: AppDatabase, modelManager: CLIPModelManager, directoryStore: DirectoryStore) {
    self.searchViewModel = SearchViewModel(
      database: database, modelManager: modelManager
    )
    self.directoryStore = directoryStore
    KeyboardShortcuts.onKeyUp(for: .activateSearch) { [self] in
      activateSearch()
    }

    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: .searchPanelDidResignKey,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      // Check on next run loop tick so the new key window is settled
      DispatchQueue.main.async {
        // Don't hide if Quick Look panel took focus
        if QLPreviewPanel.sharedPreviewPanelExists(),
           QLPreviewPanel.shared().isVisible {
          return
        }
        self.hideSearch()
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
      let panelHeight: CGFloat = 560
      let x = screenFrame.midX - panelWidth / 2
      // Top edge of panel at ~72% up the screen, matching Spotlight placement
      let panelTopY = screenFrame.origin.y + screenFrame.height * 0.72 + 100
      let y = panelTopY - panelHeight
      panel.setFrame(
        NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
        display: false
      )
    }

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

  func setSettingsOpener(_ opener: @escaping () -> Void) {
    settingsOpener = opener
  }

  func openSettings() {
    hideSearch()
    NSApplication.shared.activate(ignoringOtherApps: true)
    settingsOpener?()
  }

  private func getOrCreatePanel() -> SearchPanel {
    if let existing = searchPanel { return existing }

    let panel = SearchPanel(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 560)
    )

    let hostingView = NSHostingView(
      rootView: SearchPanelView(
        viewModel: searchViewModel,
        onDismiss: { [weak self] in
          self?.hideSearch()
        },
        onOpenSettings: { [weak self] in
          self?.openSettings()
        }
      )
      .environment(searchController)
      .environment(directoryStore)
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
  let appState: AppState
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    let _ = appState.setSettingsOpener { openSettings() }

    Button("Open Search") {
      appState.activateSearch()
    }
    .keyboardShortcut("F")

    Button("Settings...") {
      appState.openSettings()
    }
    .keyboardShortcut(",")

    Divider()

    Button("Quit") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("Q")
  }
}
