import SwiftUI

struct SettingsView: View {
  @State private var selection: Tab = .general
  
  enum Tab: Hashable {
    case general
    case shortcuts
    case about
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
    }
    .frame(width: 500, height: 300)
    .padding()
  }
  
}
