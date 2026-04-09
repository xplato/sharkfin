import SwiftUI

struct WelcomeStep: View {
  var onGetStarted: () -> Void
  var onSkip: () -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      
      Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        .resizable()
        .frame(width: 80, height: 80)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
      
      Spacer().frame(height: 24)
      
      Text("Welcome to Sharkfin")
        .font(.title)
        .fontWeight(.bold)
      
      Spacer().frame(height: 8)
      
      Text(
        "Search your files using natural language,\npowered by CLIP embeddings."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      
      Spacer().frame(height: 32)
      
      VStack(alignment: .leading, spacing: 20) {
        SetupRow(
          icon: "arrow.down.circle",
          color: .blue,
          title: "Download CLIP Models",
          description:
            "Download the text and vision encoder models to enable semantic search."
        )
        SetupRow(
          icon: "folder.badge.plus",
          color: .orange,
          title: "Add a Directory",
          description:
            "Choose a folder to index so its contents appear in search results."
        )
        SetupRow(
          icon: "magnifyingglass",
          color: .purple,
          title: "Search Your Files",
          description:
            "Use the global shortcut to search with text descriptions of what you're looking for."
        )
      }
      .padding(.horizontal, 20)
      
      Spacer()
      
      VStack(spacing: 12) {
        Button("Get Started") {
          onGetStarted()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        
        Button("Skip Setup") {
          onSkip()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      
      Spacer().frame(height: 28)
    }
    .padding(.horizontal, 40)
  }
}

private struct SetupRow: View {
  let icon: String
  let color: Color
  let title: String
  let description: String
  
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 32, alignment: .center)
      
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}
