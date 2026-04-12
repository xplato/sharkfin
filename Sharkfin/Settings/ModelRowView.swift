import SwiftUI

struct ModelPackageRowView: View {
  let package: CLIPModelPackage
  @Environment(CLIPModelManager.self) private var manager
  @Environment(IndexingService.self) private var indexingService
  @Environment(DirectoryStore.self) private var directoryStore
  @State private var showDeleteConfirmation = false
  @State private var showActivateConfirmation = false
  
  private var state: ModelDownloadState {
    manager.packageState(package)
  }
  
  private var isActive: Bool {
    manager.activePackage.id == package.id
  }
  
  private var formattedSize: String {
    ByteCountFormatter.string(
      fromByteCount: package.totalSizeBytes,
      countStyle: .file
    )
  }
  
  private var showBadge: Bool {
    switch state {
    case .downloaded, .error: true
    default:
      false
    }
  }
  
  private var badgeText: String {
    switch state {
    case .downloaded: "Downloaded"
    case .error: "Error"
    case .downloading: "Downloading"
    case .notDownloaded: "Not Downloaded"
    }
  }
  
  private var badgeColor: Color {
    switch state {
    case .downloaded: .green
    case .error: .red
    case .downloading: .blue
    case .notDownloaded: .gray
    }
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(package.displayName)
            .fontWeight(.medium)
          
          HStack(spacing: 2) {
            if showBadge {
              TextBadge(text: badgeText, color: badgeColor)
            }
            
            if isActive && state == .downloaded {
              TextBadge(text: "Active", color: .blue)
            }
          }
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("\(package.description)")
            .font(.caption)
            .foregroundStyle(.tertiary)
          Text("\(formattedSize)")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
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
        manager.downloadPackage(package)
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
          manager.cancelPackage(package)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .buttonStyle(.borderless)
      }
      
    case .downloaded:
      HStack(spacing: 8) {
        if !isActive {
          Button("Use") {
            showActivateConfirmation = true
          }
          .confirmationDialog(
            "Switch to \"\(package.displayName)\"?",
            isPresented: $showActivateConfirmation,
            titleVisibility: .visible
          ) {
            Button("Switch & Index") {
              manager.setActivePackage(package)
              indexingService.indexAllEnabled(from: directoryStore)
            }
          } message: {
            Text(
              "Directories will be indexed with this model. Files already indexed with it will be skipped."
            )
          }
        }
        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .confirmationDialog(
          "Remove \"\(package.displayName)\"?",
          isPresented: $showDeleteConfirmation,
          titleVisibility: .visible
        ) {
          Button("Remove", role: .destructive) {
            manager.deletePackage(package)
          }
        } message: {
          Text(
            "The model files and all embeddings created with this model will be deleted. You can re-download and re-index at any time."
          )
        }
      }
      
    case .error(let message):
      HStack(spacing: 8) {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
        Button("Retry") {
          manager.downloadPackage(package)
        }
      }
    }
  }
}
