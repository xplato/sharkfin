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
    .frame(minWidth: 500, idealWidth: 800, maxWidth: 1000,
           minHeight: 300, idealHeight: 500, maxHeight: 700)
    .padding()
  }
}
