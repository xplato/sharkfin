import SwiftUI

struct SettingsView: View {
  @Environment(CLIPModelManager.self) private var modelManager
  @Environment(DirectoryStore.self) private var directoryStore
  @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
  @State private var selection: Tab = .general
  
  enum Tab: Hashable {
    case general
    case shortcuts
    case advanced
    case about
  }
  
  private var shouldShowWelcome: Bool {
    !hasSeenWelcome && (!modelManager.isReady || directoryStore.directories.isEmpty)
  }

  var body: some View {
    if shouldShowWelcome {
      WelcomeView {
        hasSeenWelcome = true
      }
      .frame(minWidth: 400, idealWidth: 500, maxWidth: 600,
             minHeight: 500, idealHeight: 600, maxHeight: 900)
    } else {
      TabView(selection: $selection) {
        GeneralSettingsView()
          .tabItem {
            Label("General", systemImage: "gearshape")
          }
          .tag(Tab.general)
        
        KeyboardShortcutsView()
          .tabItem {
            Label("Shortcuts", systemImage: "keyboard")
          }
          .tag(Tab.shortcuts)
        
        AdvancedSettingsView()
          .tabItem {
            Label("Advanced", systemImage: "hammer")
          }
          .tag(Tab.advanced)
        
        AboutView()
          .tabItem {
            Label("About", systemImage: "info.circle")
          }
          .tag(Tab.about)
      }
      .frame(minWidth: 400, idealWidth: 500, maxWidth: 600,
             minHeight: 500, idealHeight: 600, maxHeight: 900)
    }
  }
}
