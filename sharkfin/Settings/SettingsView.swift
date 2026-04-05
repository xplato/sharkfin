import SwiftUI

struct SettingsView: View {
  @State private var selection: Tab = .general
  
  enum Tab: Hashable {
    case general
    case shortcuts
    case about
    case advanced
  }
  
  var body: some View {
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
      
      AboutView()
        .tabItem {
          Label("About", systemImage: "info.circle")
        }
        .tag(Tab.about)
      
      AdvancedSettingsView()
        .tabItem {
          Label("Advanced", systemImage: "hammer")
        }
        .tag(Tab.advanced)
    }
    .frame(minWidth: 400, idealWidth: 500, maxWidth: 600,
           minHeight: 500, idealHeight: 600, maxHeight: 900)
  }
}
