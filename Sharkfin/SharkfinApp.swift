import KeyboardShortcuts
import Quartz
import SwiftUI

@main
struct SharkfinApp: App {
  @State private var directoryStore: DirectoryStore
  @State private var modelManager: CLIPModelManager
  @State private var indexingService: IndexingService
  @State private var directoryWatcher: DirectoryWatcherService
  @State private var appState: AppState

  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.openSettings) private var openSettings

  init() {
    let manager = CLIPModelManager()
    _modelManager = State(initialValue: manager)
    let indexing = IndexingService(database: .shared, modelManager: manager)
    _indexingService = State(initialValue: indexing)
    let store = DirectoryStore(database: .shared)
    _directoryStore = State(initialValue: store)
    let watcher = DirectoryWatcherService()
    _directoryWatcher = State(initialValue: watcher)
    _appState = State(
      initialValue: AppState(
        database: .shared,
        modelManager: manager,
        directoryStore: store
      )
    )

    // Give the AppDelegate references so it can start services on launch
    appDelegate.directoryWatcher = watcher
    appDelegate.directoryStore = store
    appDelegate.indexingService = indexing
  }

  var body: some Scene {
    let _ = { appDelegate.settingsOpener = { openSettings() } }()

    MenuBarExtra("Sharkfin", image: "MenuBarIcon") {
      MenuBarContent(appState: appState)
    }

    Window("About Sharkfin", id: "about") {
      AboutView()
        .frame(width: 500, height: 220)
    }
    .windowResizability(.contentSize)
    .windowStyle(.titleBar)
    .defaultPosition(.center)

    Settings {
      SettingsView()
        .environment(directoryStore)
        .environment(modelManager)
        .environment(indexingService)
        .environment(directoryWatcher)
    }
  }
}

@MainActor
@Observable
final class AppState {
  private var searchPanel: SearchPanel?
  private var searchViewModel: SearchViewModel
  private var searchController = SearchController()
  let modelManager: CLIPModelManager
  let directoryStore: DirectoryStore
  private var resignKeyObserver: Any?
  private var settingsOpener: (() -> Void)?
  private var hasPositionedPanel = false

  var needsSetup: Bool {
    !UserDefaults.standard.bool(forKey: StorageKey.hasSeenWelcome)
  }

  init(
    database: AppDatabase,
    modelManager: CLIPModelManager,
    directoryStore: DirectoryStore
  ) {
    self.searchViewModel = SearchViewModel(
      database: database,
      modelManager: modelManager
    )
    self.modelManager = modelManager
    self.directoryStore = directoryStore
    KeyboardShortcuts.onKeyDown(for: .activateSearch) { [self] in
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
          QLPreviewPanel.shared().isVisible
        {
          return
        }
        self.hideSearch()
      }
    }
  }

  func activateSearch() {
    if needsSetup {
      openSettings()
      return
    }
    if let panel = searchPanel, panel.isVisible {
      hideSearch()
    } else {
      showSearch()
    }
  }

  private func showSearch() {
    let panel = getOrCreatePanel()

    // Only set the default position on first show; subsequent shows
    // preserve the user's dragged position (resets on app relaunch).
    if !hasPositionedPanel {
      if let screen = NSScreen.screens.first(where: {
        $0.frame.contains(NSEvent.mouseLocation)
      }) ?? NSScreen.main ?? NSScreen.screens.first {
        let screenFrame = screen.visibleFrame
        let panelWidth = SearchPanel.panelWidth
        let panelHeight = SearchPanel.panelHeight
        let x = screenFrame.midX - panelWidth / 2
        let panelTopY = screenFrame.origin.y + screenFrame.height * 0.78 + 100
        let y = panelTopY - panelHeight
        panel.setFrame(
          NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
          display: false
        )
        panel.defaultOriginY = y
      }
      hasPositionedPanel = true
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
    if let settingsOpener {
      settingsOpener()
    } else {
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    // When the settings window is already open, the opener alone won't
    // bring it to the front. Explicitly make it key on the next tick
    // so the window is resolved.
    DispatchQueue.main.async {
      for window in NSApplication.shared.windows
      where !(window is SearchPanel) && window.isVisible {
        window.makeKeyAndOrderFront(nil)
        break
      }
    }
  }

  private func getOrCreatePanel() -> SearchPanel {
    if let existing = searchPanel { return existing }

    let panel = SearchPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: SearchPanel.panelWidth,
        height: SearchPanel.panelHeight
      )
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
    hostingView.layer?.cornerRadius = SearchPanel.cornerRadius
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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  private var welcomeWindow: NSWindow?
  var settingsOpener: (() -> Void)?
  var directoryWatcher: DirectoryWatcherService?
  var directoryStore: DirectoryStore?
  var indexingService: IndexingService?

  func applicationDidFinishLaunching(_ notification: Notification) {
    LoggingService.shared.info("App launched", category: "App")

    // Start FSEvents directory watcher and index on launch
    if let watcher = directoryWatcher,
      let store = directoryStore,
      let indexing = indexingService
    {
      watcher.start(directoryStore: store, indexingService: indexing)

      let indexOnLaunch =
        UserDefaults.standard.object(forKey: StorageKey.indexOnLaunch) as? Bool
        ?? true
      if indexOnLaunch, indexing.modelsReady {
        indexing.indexAllEnabled(from: store)
      }
    }

    guard !UserDefaults.standard.bool(forKey: StorageKey.hasSeenWelcome) else {
      return
    }

    let welcomeView = WelcomeView { [weak self] in
      UserDefaults.standard.set(true, forKey: StorageKey.hasSeenWelcome)
      // Defer window teardown so the button action finishes
      // before the hosting view hierarchy is destroyed.
      DispatchQueue.main.async {
        self?.welcomeWindow?.close()
        self?.welcomeWindow = nil
        // Open settings after dismissing the welcome window
        self?.settingsOpener?()
        NSApp.activate(ignoringOtherApps: true)
      }
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: welcomeView)
    window.title = "Welcome to Sharkfin"
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    self.welcomeWindow = window
  }
}

struct MenuBarContent: View {
  let appState: AppState
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    let _ = appState.setSettingsOpener { openSettings() }

    Button("Open Search") {
      appState.activateSearch()
    }

    Button("Settings...") {
      appState.openSettings()
    }
    .keyboardShortcut(",")

    Divider()

    Button("About Sharkfin") {
      openWindow(id: "about")
      NSApp.activate(ignoringOtherApps: true)
    }

    Button("Quit") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("Q")
  }
}
