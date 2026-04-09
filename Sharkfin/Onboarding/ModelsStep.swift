import SwiftUI

struct ModelsStep: View {
  let modelManager: CLIPModelManager
  var onContinue: () -> Void
  var onSkip: () -> Void
  
  private var allDownloaded: Bool {
    modelManager.isReady
  }
  
  private var isDownloading: Bool {
    CLIPModelSpec.all.contains { model in
      if case .downloading = modelManager.modelStates[model.id] ?? .notDownloaded {
        return true
      }
      return false
    }
  }
  
  private var hasError: Bool {
    CLIPModelSpec.all.contains { model in
      if case .error = modelManager.modelStates[model.id] ?? .notDownloaded {
        return true
      }
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
      
      Text("These models power semantic search. Both are required for full functionality.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
      
      Spacer().frame(height: 24)
      
      VStack(spacing: 12) {
        ForEach(CLIPModelSpec.all) { model in
          OnboardingModelRow(model: model, modelManager: modelManager)
        }
      }
      .padding(.horizontal, 30)
      
      if allDownloaded {
        Spacer().frame(height: 16)
        
        Label("Both models downloaded", systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.green)
      }
      
      if hasError {
        Spacer().frame(height: 12)
        
        Link(
          destination: URL(string: "https://github.com/xplato/Sharkfin?tab=readme-ov-file#1-downloading-clip-models")!
        ) {
          Label("Troubleshooting guide", systemImage: "questionmark.circle")
            .font(.caption)
        }
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
        .disabled(!allDownloaded || isDownloading)
        
        Button("Skip this step") {
          onSkip()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      
      Spacer().frame(height: 28)
    }
    .padding(.horizontal, 24)
  }
}

// MARK: - Onboarding Model Row

private struct OnboardingModelRow: View {
  let model: CLIPModelSpec
  let modelManager: CLIPModelManager
  
  private var state: ModelDownloadState {
    modelManager.modelStates[model.id] ?? .notDownloaded
  }
  
  private var formattedSize: String {
    ByteCountFormatter.string(
      fromByteCount: model.totalSizeBytes,
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
        Text(model.displayName)
          .font(.callout)
          .fontWeight(.medium)
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
        modelManager.download(model)
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
          modelManager.cancel(model)
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
          modelManager.retry(model)
        }
        .controlSize(.small)
      }
    }
  }
}
