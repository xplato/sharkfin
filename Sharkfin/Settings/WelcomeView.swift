import SwiftUI

// MARK: - Onboarding Step

private enum OnboardingStep: Int, CaseIterable {
  case welcome
  case models
  case directories
  case complete
}

// MARK: - WelcomeView

struct WelcomeView: View {
  var onComplete: () -> Void
  
  @Environment(CLIPModelManager.self) private var modelManager
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(IndexingService.self) private var indexingService
  @Environment(AppState.self) private var appState
  
  @State private var currentStep: OnboardingStep = .welcome
  @State private var showSkipConfirmation = false
  
  var body: some View {
    VStack(spacing: 0) {
      if currentStep != .welcome {
        StepIndicator(currentStep: currentStep) { step in
          currentStep = step
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
      }
      
      Group {
        switch currentStep {
        case .welcome:
          WelcomeStep(
            onGetStarted: { advanceTo(.models) },
            onSkip: { showSkipConfirmation = true }
          )
        case .models:
          ModelsStep(
            modelManager: modelManager,
            onContinue: { advanceTo(.directories) },
            onSkip: { advanceTo(.directories) }
          )
        case .directories:
          DirectoriesStep(
            directoryStore: directoryStore,
            indexingService: indexingService,
            onContinue: { advanceTo(.complete) },
            onSkip: { advanceTo(.complete) }
          )
        case .complete:
          CompleteStep(
            onOpenSearch: {
              onComplete()
              // Defer search activation so the window teardown finishes first
              DispatchQueue.main.async {
                appState.activateSearch()
              }
            },
            onGoToSettings: {
              onComplete()
            }
          )
        }
      }
      .transition(.push(from: .trailing))
    }
    .frame(width: 480, height: 560)
    .animation(.easeInOut(duration: 0.3), value: currentStep)
    .alert(
      "Skip Setup?",
      isPresented: $showSkipConfirmation
    ) {
      Button("Skip", role: .destructive) {
        onComplete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can always configure models and directories in Settings later.")
    }
  }
  
  private func advanceTo(_ step: OnboardingStep) {
    currentStep = step
  }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
  let currentStep: OnboardingStep
  var onNavigate: (OnboardingStep) -> Void
  
  private let steps: [(step: OnboardingStep, label: String)] = [
    (.models, "Models"),
    (.directories, "Directories"),
    (.complete, "Done"),
  ]
  
  var body: some View {
    HStack(spacing: 6) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
        if index > 0 {
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.quaternary)
        }
        
        let isCompleted = item.step.rawValue < currentStep.rawValue
        let isCurrent = item.step == currentStep
        let canNavigate = isCompleted
        
        Button {
          if canNavigate {
            onNavigate(item.step)
          }
        } label: {
          HStack(spacing: 4) {
            if isCompleted {
              Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            }
            
            Text(item.label)
              .font(.caption)
              .fontWeight(isCurrent ? .semibold : .regular)
          }
          .foregroundStyle(isCurrent ? .primary : .secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            isCurrent ? Color.accentColor.opacity(0.12) : Color.clear,
            in: Capsule()
          )
        }
        .buttonStyle(.plain)
        .disabled(!canNavigate)
      }
    }
  }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
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

// MARK: - Models Step

private struct ModelsStep: View {
  let modelManager: CLIPModelManager
  var onContinue: () -> Void
  var onSkip: () -> Void
  
  private var allDownloaded: Bool {
    modelManager.isReady
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
        .disabled(!allDownloaded)
        
        Button("Skip this step") {
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

// MARK: - Directories Step

private struct DirectoriesStep: View {
  let directoryStore: DirectoryStore
  let indexingService: IndexingService
  var onContinue: () -> Void
  var onSkip: () -> Void
  
  private var hasDirectories: Bool {
    !directoryStore.directories.isEmpty
  }
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 16)
      
      Text("Add Directories")
        .font(.title2)
        .fontWeight(.semibold)
      
      Spacer().frame(height: 6)
      
      Text("Choose folders to index. Their contents will be searchable once indexed.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
      
      Spacer().frame(height: 24)
      
      VStack(spacing: 12) {
        if directoryStore.directories.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text("No directories added yet")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 24)
        } else {
          ScrollView {
            VStack(spacing: 8) {
              ForEach(directoryStore.directories) { directory in
                OnboardingDirectoryRow(
                  directory: directory,
                  indexingService: indexingService
                )
              }
            }
          }
          .frame(maxHeight: 180)
        }
        
        AddDirectoryButton()
          .buttonStyle(.bordered)
      }
      .padding(.horizontal, 30)
      
      Spacer()
      
      VStack(spacing: 12) {
        Button("Continue") {
          onContinue()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!hasDirectories)
        
        Button("Skip this step") {
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

// MARK: - Onboarding Directory Row

private struct OnboardingDirectoryRow: View {
  let directory: SharkfinDirectory
  let indexingService: IndexingService
  
  private var progress: IndexingProgress? {
    guard let id = directory.id else { return nil }
    return indexingService.progressByDirectory[id]
  }
  
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "folder.fill")
        .foregroundStyle(.blue)
        .frame(width: 20)
      
      VStack(alignment: .leading, spacing: 2) {
        Text(directory.label ?? directory.path)
          .font(.callout)
          .fontWeight(.medium)
          .lineLimit(1)
        
        Text(formatDisplayPath(directory.path))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
      
      Spacer()
      
      if let progress {
        statusView(for: progress)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
  }
  
  @ViewBuilder
  private func statusView(for progress: IndexingProgress) -> some View {
    switch progress.phase {
    case .scanning:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.small)
        Text("Scanning...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .indexing:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.small)
        Text("\(progress.processed)/\(progress.total)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    case .complete(let count):
      Label("\(count) indexed", systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(.green)
    case .upToDate:
      Label("Up to date", systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(.green)
    case .error(let message):
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
        .lineLimit(1)
    case .cancelled:
      Text("Cancelled")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Complete Step

private struct CompleteStep: View {
  var onOpenSearch: () -> Void
  var onGoToSettings: () -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 56))
        .foregroundStyle(.green)
      
      Spacer().frame(height: 20)
      
      Text("You're All Set!")
        .font(.title)
        .fontWeight(.bold)
      
      Spacer().frame(height: 8)
      
      Text(
        "Sharkfin is ready to go. Use the global shortcut\nor click below to start searching."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      
      Spacer()
      
      VStack(spacing: 12) {
        Button("Open Search") {
          onOpenSearch()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        
        Button("Go to Settings") {
          onGoToSettings()
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      
      Spacer().frame(height: 28)
    }
    .padding(.horizontal, 40)
  }
}
