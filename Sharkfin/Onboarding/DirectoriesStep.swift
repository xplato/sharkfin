import SwiftUI

struct DirectoriesStep: View {
  let directoryStore: DirectoryStore
  let indexingService: IndexingService
  var onContinue: () -> Void
  var onSkip: () -> Void
  
  private var hasDirectories: Bool {
    !directoryStore.directories.isEmpty
  }
  
  private var isIndexing: Bool {
    directoryStore.directories.contains { directory in
      guard let id = directory.id else { return false }
      guard let progress = indexingService.progressByDirectory[id] else { return false }
      switch progress.phase {
      case .scanning, .indexing:
        return true
      default:
        return false
      }
    }
  }
  
  private var allFinished: Bool {
    hasDirectories && directoryStore.directories.allSatisfy { directory in
      guard let id = directory.id else { return false }
      guard let progress = indexingService.progressByDirectory[id] else { return false }
      switch progress.phase {
      case .complete, .upToDate:
        return true
      default:
        return false
      }
    }
  }
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 16)
      
      Text("Add Directories")
        .font(.title2)
        .fontWeight(.semibold)
      
      Spacer().frame(height: 6)
      
      Text("Choose folders to scan and make searchable. Everything stays on your Mac.")
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
                  directoryStore: directoryStore,
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
        if isIndexing && !allFinished {
          Text("Indexing will continue in the background. You can start searching immediately.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
        }
        
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
        .opacity(hasDirectories ? 0 : 1)
        .disabled(hasDirectories)
      }
      
      Spacer().frame(height: 28)
    }
    .padding(.horizontal, 40)
  }
}

// MARK: - Onboarding Directory Row

private struct OnboardingDirectoryRow: View {
  let directory: SharkfinDirectory
  let directoryStore: DirectoryStore
  let indexingService: IndexingService
  
  @State private var showRemoveConfirmation = false
  
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
      
      Button {
        showRemoveConfirmation = true
      } label: {
        Image(systemName: "xmark")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .confirmationDialog(
        "Remove \"\(directory.label ?? directory.path)\"?",
        isPresented: $showRemoveConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) {
          if let id = directory.id {
            try? directoryStore.database.deleteDirectory(id: id)
          }
        }
      } message: {
        Text("This directory will no longer be indexed. You can re-add it later.")
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
