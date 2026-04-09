import SwiftUI

extension Notification.Name {
  static let viewStateDidReset = Notification.Name("viewStateDidReset")
}

struct SettingsView: View {
  // Local state decoupled from @AppStorage so the CompleteStep's
  // direct UserDefaults write doesn't immediately switch to tabs.
  @State private var showOnboarding: Bool
  @State private var selection: Tab = .general
  
  init() {
    _showOnboarding = State(
      initialValue: !UserDefaults.standard.bool(forKey: StorageKey.hasSeenWelcome)
    )
  }
  
  enum Tab: Hashable {
    case general
    case advanced
  }
  
  var body: some View {
    if showOnboarding {
      WelcomeView(onComplete: {
        showOnboarding = false
      })
      .frame(
        minWidth: 480,
        idealWidth: 500,
        maxWidth: 600,
        minHeight: 560,
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
            Label("Advanced", systemImage: "slider.horizontal.3")
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
      .onReceive(NotificationCenter.default.publisher(for: .viewStateDidReset)) { _ in
        showOnboarding = true
      }
    }
  }
}
