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
  
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: iconName)
        .foregroundStyle(iconColor)
        .font(.title3)
      
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(package.displayName)
            .fontWeight(.medium)
          if isActive && state == .downloaded {
            Text("Active")
              .font(.caption2)
              .fontWeight(.medium)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.blue.opacity(0.15))
              .foregroundStyle(.blue)
              .clipShape(Capsule())
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
            Button("Switch & Re-index") {
              manager.setActivePackage(package)
              indexingService.indexAllEnabled(from: directoryStore)
            }
          } message: {
            Text(
              "All indexed directories will be re-indexed with the new model. This may take a while depending on the number of files."
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
            "The model files will be deleted. You can re-download them at any time."
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
