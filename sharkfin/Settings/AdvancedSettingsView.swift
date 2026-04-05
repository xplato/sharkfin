import SwiftUI

struct AdvancedSettingsView: View {
  /// All `@AppStorage` keys used for dialog suppression toggles.
  /// Add new keys here as more "Don't show again" dialogs are introduced.
  private static let suppressionKeys = [
    "suppressDisableDirectoryWarning",
  ]

  @Environment(IndexingService.self) private var indexingService
  @State private var stats: AppDatabase.Stats?
  @State private var showResetConfirmation = false

  private var activeJobCount: Int {
    indexingService.progressByDirectory.values.filter { progress in
      switch progress.phase {
      case .scanning, .indexing: true
      default: false
      }
    }.count
  }

  var body: some View {
    Form {
      Section("Database") {
        if let stats {
          LabeledContent("Indexed files") {
            Text("\(stats.totalFiles)")
              .monospacedDigit()
          }

          LabeledContent("Embeddings") {
            Text("\(stats.totalEmbeddings)")
              .monospacedDigit()
          }

          LabeledContent("Directories") {
            Text("\(stats.enabledDirectories) of \(stats.totalDirectories) enabled")
              .monospacedDigit()
          }

          LabeledContent("Source file size") {
            Text(formattedBytes(stats.totalSizeBytes))
              .monospacedDigit()
          }

          LabeledContent("Database size") {
            Text(formattedBytes(stats.databaseSizeBytes))
              .monospacedDigit()
          }

          LabeledContent("Thumbnails size") {
            Text(formattedBytes(stats.thumbnailsSizeBytes))
              .monospacedDigit()
          }

          LabeledContent("Last indexed") {
            if let date = stats.lastIndexedAt {
              Text(date, format: .relative(presentation: .named))
            } else {
              Text("Never")
                .foregroundStyle(.secondary)
            }
          }

          if activeJobCount > 0 {
            LabeledContent("Active jobs") {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.small)
                Text("\(activeJobCount)")
                  .monospacedDigit()
              }
            }
          }
        } else {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
      }

      Section("Storage") {
        HStack {
          Text(AppDatabase.dataDirectoryURL.path(percentEncoded: false))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

          Spacer()

          Button("Open in Finder") {
            NSWorkspace.shared.open(AppDatabase.dataDirectoryURL)
          }
        }
      }

      Section("Warnings") {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Reset All Warnings")
            Text("Show confirmation dialogs that were previously dismissed with \"Don't show again.\"")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Reset") {
            showResetConfirmation = true
          }
          .alert("Reset All Warnings?", isPresented: $showResetConfirmation) {
            Button("Reset") {
              for key in Self.suppressionKeys {
                UserDefaults.standard.removeObject(forKey: key)
              }
            }
            Button("Cancel", role: .cancel) { }
          } message: {
            Text("All previously suppressed confirmation dialogs will be shown again.")
          }
        }
      }
    }
    .formStyle(.grouped)
    .task {
      await refreshStats()
    }
    .onChange(of: activeJobCount) {
      Task { await refreshStats() }
    }
  }

  private func refreshStats() async {
    do {
      let db = AppDatabase.shared
      let fetched = try db.fetchStats()
      stats = fetched
    } catch {
      print("Failed to fetch database stats: \(error)")
    }
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
