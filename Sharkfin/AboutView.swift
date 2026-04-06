import SwiftUI

struct AboutView: View {
  private var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "Unknown"
  }

  private var build: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
  }

  var body: some View {
    VStack(spacing: 12) {
      Text("Sharkfin")
        .font(.largeTitle)

      Text("Version \(version) (\(build))")
        .font(.callout)
        .foregroundColor(.secondary)

      Link(
        "GitHub Repository",
        destination: URL(string: "https://github.com/xplato/sharkfin")!
      )
      .font(.callout)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .multilineTextAlignment(.center)
  }
}
