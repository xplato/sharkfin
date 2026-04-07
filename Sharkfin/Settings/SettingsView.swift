import SwiftUI

struct SettingsView: View {
  @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
  @State private var selection: Tab = .general

  enum Tab: Hashable {
    case general
    case advanced
  }

  var body: some View {
    if !hasSeenWelcome {
      WelcomeView {
        hasSeenWelcome = true
      }
      .frame(
        minWidth: 400,
        idealWidth: 500,
        maxWidth: 600,
        minHeight: 500,
        idealHeight: 600,
        maxHeight: 900
      )
    } else {
      TabView(selection: $selection) {
        GeneralSettingsView()
          .tabItem {
            Label("General", systemImage: "gearshape")
          }
          .tag(Tab.general)

        AdvancedSettingsView()
          .tabItem {
            Label("Advanced", systemImage: "hammer")
          }
          .tag(Tab.advanced)
      }
      .frame(
        minWidth: 400,
        idealWidth: 500,
        maxWidth: 600,
        minHeight: 500,
        idealHeight: 600,
        maxHeight: 900
      )
    }
  }
}
