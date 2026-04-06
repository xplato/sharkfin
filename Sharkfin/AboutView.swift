import SwiftUI

struct AboutView: View {
  private var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "Unknown"
  }

  private var build: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
  }

  private var copyrightString: String {
    Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
      ?? "Copyright \u{00A9} 2026 Tristan Brewster. All rights reserved."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 24) {
        // App icon
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 128, height: 128)

        // App info
        VStack(alignment: .leading, spacing: 6) {
          Text("Sharkfin")
            .font(.system(size: 36, weight: .regular))

          Text("Version \(version) (\(build))")
            .font(.callout)
            .foregroundStyle(.secondary)

          Spacer()
            .frame(height: 8)

          Text(copyrightString)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
      }

      Spacer()

      // Button aligned with the text column
      Button("GitHub Repository") {
        if let url = URL(string: "https://github.com/xplato/sharkfin") {
          NSWorkspace.shared.open(url)
        }
      }
      .controlSize(.large)
      .padding(.leading, 128 + 24) // icon width + HStack spacing
    }
    .padding(.top, 24)
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
