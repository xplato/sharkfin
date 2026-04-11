import SwiftUI

struct ModelsStep: View {
  let modelManager: CLIPModelManager
  var onContinue: () -> Void
  var onSkip: () -> Void
  
  private var anyPackageReady: Bool {
    CLIPModelPackage.all.contains { modelManager.isPackageReady($0) }
  }
  
  private var anyDownloading: Bool {
    CLIPModelPackage.all.contains {
      if case .downloading = modelManager.packageState($0) { return true }
      return false
    }
  }
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 16)
      
      Text("Download CLIP Models")
        .font(.title2)
        .fontWeight(.semibold)
      
      Spacer().frame(height: 6)
      
      Text("These models power semantic search. This is the only step that requires internet—after download, Sharkfin runs entirely offline.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
      
      Spacer().frame(height: 24)
      
      VStack(spacing: 10) {
        ForEach(CLIPModelPackage.all) { package in
          OnboardingPackageRow(
            package: package,
            modelManager: modelManager,
            isRecommended: package.id == CLIPModelPackage.vitB32.id
          )
        }
      }
      .padding(.horizontal, 30)
      
      if anyPackageReady {
        Spacer().frame(height: 16)
        
        Label("Ready to continue", systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.green)
      }
      
      Spacer()
      
      VStack(spacing: 8) {
        Link(
          destination: URL(string: "https://github.com/xplato/Sharkfin?tab=readme-ov-file#1-downloading-clip-models")!
        ) {
          Label("Download models manually", systemImage: "arrow.up.forward.square")
            .font(.caption)
        }
        
        Spacer().frame(height: 4)
        
        Button("Continue") {
          onContinue()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!anyPackageReady || anyDownloading)
        
        Button("Skip this step") {
          onSkip()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .opacity(anyPackageReady ? 0 : 1)
        .disabled(anyPackageReady)
      }
      
      Spacer().frame(height: 28)
    }
    .padding(.horizontal, 24)
  }
}

// MARK: - Onboarding Package Row

private struct OnboardingPackageRow: View {
  let package: CLIPModelPackage
  let modelManager: CLIPModelManager
  let isRecommended: Bool
  
  private var state: ModelDownloadState {
    modelManager.packageState(package)
  }
  
  private var formattedSize: String {
    ByteCountFormatter.string(
      fromByteCount: package.totalSizeBytes,
      countStyle: .file
    )
  }
  
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .foregroundStyle(iconColor)
        .font(.title3)
        .frame(width: 24)
      
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(package.displayName)
            .font(.callout)
            .fontWeight(.medium)
          if isRecommended {
            Text("Recommended")
              .font(.caption2)
              .fontWeight(.medium)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.blue.opacity(0.15))
              .foregroundStyle(.blue)
              .clipShape(Capsule())
          }
        }
        Text(package.description)
          .font(.caption)
          .foregroundStyle(.tertiary)
        Text(formattedSize)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      
      Spacer()
      
      statusContent
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
        modelManager.downloadPackage(package)
      }
      .controlSize(.small)
      
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .frame(width: 80)
        Text("\(Int(progress * 100))%")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        Button {
          modelManager.cancelPackage(package)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
      }
      
    case .downloaded:
      Image(systemName: "checkmark")
        .foregroundStyle(.green)
        .fontWeight(.semibold)
      
    case .error(let message):
      HStack(spacing: 6) {
        Text(message)
          .font(.caption2)
          .foregroundStyle(.red)
          .lineLimit(1)
          .frame(maxWidth: 100, alignment: .trailing)
        Button("Retry") {
          modelManager.downloadPackage(package)
        }
        .controlSize(.small)
      }
    }
  }
}
