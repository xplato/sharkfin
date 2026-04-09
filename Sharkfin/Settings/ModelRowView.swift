import SwiftUI

struct ModelRowView: View {
  let model: CLIPModelSpec
  @Environment(CLIPModelManager.self) private var manager
  @State private var showDeleteConfirmation = false
  
  private var state: ModelDownloadState {
    manager.modelStates[model.id] ?? .notDownloaded
  }
  
  private var formattedSize: String {
    ByteCountFormatter.string(
      fromByteCount: model.totalSizeBytes,
      countStyle: .file
    )
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: iconName)
        .foregroundStyle(iconColor)
        .font(.title3)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(model.displayName)
          .fontWeight(.medium)
        Text(formattedSize)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      
      Spacer()
      
      statusContent
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 6)
  }
  
  private var iconName: String {
    switch state {
    case .downloaded: "checkmark.circle.fill"
    case .downloading: "arrow.down.circle"
    case .error: "exclamationmark.triangle.fill"
    case .notDownloaded: "arrow.down.to.line"
    }
  }
  
  private var iconColor: Color {
    switch state {
    case .downloaded: .green
    case .downloading: .accentColor
    case .error: .red
    case .notDownloaded: .secondary
    }
  }
  
  @ViewBuilder
  private var statusContent: some View {
    switch state {
    case .notDownloaded:
      Button("Download") {
        manager.download(model)
      }
      
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .frame(width: 100)
        Text("\(Int(progress * 100))%")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        Button {
          manager.cancel(model)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .buttonStyle(.borderless)
      }
      
    case .downloaded:
      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .confirmationDialog(
        "Remove \"\(model.displayName)\"?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) {
          manager.delete(model)
        }
      } message: {
        Text(
          "The model files will be deleted. You can re-download them at any time."
        )
      }
      
    case .error(let message):
      HStack(spacing: 8) {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
        Button("Retry") {
          manager.retry(model)
        }
      }
    }
  }
}
