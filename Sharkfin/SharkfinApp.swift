import KeyboardShortcuts
import SwiftUI

@main
struct SharkfinApp: App {
  @State private var directoryStore: DirectoryStore
  @State private var modelManager: CLIPModelManager
  @State private var indexingService: IndexingService
  @State private var directoryWatcher: DirectoryWatcherService
  @State private var appState: AppState
  
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  
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
        directoryStore: store,
        indexingService: indexing
      )
    )
    
    // Give the AppDelegate references so it can start services on launch
    appDelegate.directoryWatcher = watcher
    appDelegate.directoryStore = store
    appDelegate.indexingService = indexing
    appDelegate.appState = appState
    appDelegate.modelManager = manager
  }
  
  var body: some Scene {
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
  }
}

@MainActor
@Observable
final class AppState {
  let modelManager: CLIPModelManager
  let directoryStore: DirectoryStore
  let indexingService: IndexingService
  
  private var searchPanel: SearchPanel?
  private var settingsWindow: NSWindow?
  private var searchViewModel: SearchViewModel
  private var searchController = SearchController()
  private var resignKeyObserver: Any?
  private var hasPositionedPanel = false
  
  var needsSetup: Bool {
    !UserDefaults.standard.bool(forKey: StorageKey.hasSeenWelcome)
  }
  
  init(
    database: AppDatabase,
    modelManager: CLIPModelManager,
    directoryStore: DirectoryStore,
    indexingService: IndexingService
  ) {
    self.searchViewModel = SearchViewModel(
      database: database,
      modelManager: modelManager
    )
    self.modelManager = modelManager
    self.directoryStore = directoryStore
    self.indexingService = indexingService
    
    KeyboardShortcuts.onKeyDown(for: .activateSearch) { [self] in
      activateSearch()
    }
    
    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: .searchPanelDidResignKey,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      DispatchQueue.main.async {
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
  
  func openSettings() {
    hideSearch()
    NSApp.setActivationPolicy(.regular)
    let window = getOrCreateSettingsWindow()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // Re-activate on the next run-loop tick so the window server
    // places the app at the front of the Cmd-Tab list, even if the
    // activation policy change hadn't fully propagated above.
    DispatchQueue.main.async {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
  
  private func getOrCreateSettingsWindow() -> NSWindow {
    if let existing = settingsWindow { return existing }
    
    let settingsView = SettingsView()
      .environment(directoryStore)
      .environment(modelManager)
      .environment(indexingService)
      .environment(self)
    
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: settingsView)
    window.title = "Sharkfin Settings"
    window.setContentSize(NSSize(width: 500, height: 600))
    window.minSize = NSSize(width: 400, height: 500)
    window.maxSize = NSSize(width: 600, height: 900)
    window.center()
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    
    self.settingsWindow = window
    return window
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
      .environment(modelManager)
      .environment(indexingService)
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
  private var windowCloseObserver: Any?
  private var windowBecameKeyObserver: Any?
  var directoryWatcher: DirectoryWatcherService?
  var directoryStore: DirectoryStore?
  var indexingService: IndexingService?
  var appState: AppState?
  var modelManager: CLIPModelManager?
  
  /// Intercept the system's Cmd-, / Preferences menu item so it routes
  /// to our managed settings window instead of the (removed) Settings scene.
  @objc func orderFrontPreferencesPanel(_ sender: Any?) {
    appState?.openSettings()
  }
  
  /// Also intercept the newer `showSettingsWindow:` selector used by SwiftUI.
  @objc func showSettingsWindow(_ sender: Any?) {
    appState?.openSettings()
  }
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    LoggingService.shared.info("App launched", category: "App")
    
    // Start FSEvents directory watcher and index on launch
    if let watcher = directoryWatcher,
       let store = directoryStore,
       let indexing = indexingService
    {
      watcher.start(directoryStore: store, indexingService: indexing)
      
      if indexing.modelsReady {
        indexing.indexAllEnabled(from: store)
      }
    }
    
    // Show the dock icon whenever a titled window becomes key (catches
    // system-initiated settings opening via Cmd-, as well as our own paths).
    windowBecameKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let window = notification.object as? NSWindow,
            !(window is SearchPanel),
            window.styleMask.contains(.titled) else { return }
      DispatchQueue.main.async {
        self?.updateActivationPolicy()
      }
    }
    
    // Revert dock icon when no standard windows remain after a close.
    windowCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      DispatchQueue.main.async {
        self?.updateActivationPolicy()
      }
    }
    
    guard !UserDefaults.standard.bool(forKey: StorageKey.hasSeenWelcome) else {
      return
    }
    
    let welcomeView = WelcomeView(onComplete: { [weak self] skipped in
      UserDefaults.standard.set(true, forKey: StorageKey.hasSeenWelcome)
      // Defer window teardown so the button action finishes
      // before the hosting view hierarchy is destroyed.
      DispatchQueue.main.async {
        self?.welcomeWindow?.close()
        self?.welcomeWindow = nil
        if skipped {
          self?.appState?.openSettings()
        }
      }
    })
      .environment(modelManager!)
      .environment(directoryStore!)
      .environment(indexingService!)
      .environment(appState!)
    
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: welcomeView)
    window.title = "Welcome to Sharkfin"
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    
    self.welcomeWindow = window
  }
  
  /// Shows the dock icon when titled windows are visible, hides it otherwise.
  func updateActivationPolicy() {
    let hasVisibleStandardWindow = NSApplication.shared.windows.contains { window in
      window.isVisible
      && window.styleMask.contains(.titled)
      && !(window is SearchPanel)
    }
    
    let desired: NSApplication.ActivationPolicy = hasVisibleStandardWindow ? .regular : .accessory
    if NSApp.activationPolicy() != desired {
      NSApp.setActivationPolicy(desired)
      if desired == .regular {
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }
}

struct MenuBarContent: View {
  let appState: AppState
  
  @Environment(\.openWindow) private var openWindow
  
  var body: some View {
    Button("Open Search") {
      appState.activateSearch()
    }
    
    Button("Settings...") {
      appState.openSettings()
    }
    .keyboardShortcut(",")
    
    Divider()
    
    Button("About Sharkfin") {
      NSApp.setActivationPolicy(.regular)
      openWindow(id: "about")
      NSApp.activate(ignoringOtherApps: true)
    }
    
    Button("Quit") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("Q")
  }
}
