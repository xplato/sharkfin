import SwiftUI

struct AdvancedSettingsView: View {
  /// All `@AppStorage` keys used for dialog suppression toggles.
  /// Add new keys here as more "Don't show again" dialogs are introduced.
  private static let suppressionKeys = [
    "suppressDisableDirectoryWarning"
  ]
  
  private static let defaultExcludedFolders = [
    "node_modules", "__pycache__",
  ]
  
  @Environment(IndexingService.self) private var indexingService
  @Environment(DirectoryWatcherService.self) private var directoryWatcher
  @AppStorage(StorageKey.watchDirectories) private var watchDirectories = true
  @AppStorage(StorageKey.indexOnLaunch) private var indexOnLaunch = true
  @AppStorage(StorageKey.ignoreHiddenDirectories) private
  var ignoreHiddenDirectories =
  true
  @AppStorage(StorageKey.debugMode) private var debugMode = false
  @State private var excludedFolderNames: [String] = []
  @State private var newFolderName = ""
  @State private var stats: AppDatabase.Stats?
  @State private var showResetConfirmation = false
  @State private var showResetViewStateConfirmation = false
  
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
      Section("Indexing") {
        Toggle(isOn: $watchDirectories) {
          Text("Watch for changes")
          Text(
            "Automatically index enabled directories after file system changes."
          )
        }
        .onChange(of: watchDirectories) { _, _ in
          directoryWatcher.restartIfNeeded()
        }
        Toggle(isOn: $indexOnLaunch) {
          Text("Index on launch")
          Text(
            "Automatically index enabled directories when Sharkfin launches."
          )
        }
        Toggle(
          "Ignore files in hidden directories",
          isOn: $ignoreHiddenDirectories
        )
      }
      
      Section {
        ForEach(excludedFolderNames, id: \.self) { name in
          HStack {
            Text(name)
              .font(.body.monospaced())
            Spacer()
            Button {
              removeFolder(name)
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
          }
        }
        
        HStack {
          TextField("Folder name", text: $newFolderName)
            .font(.body.monospaced())
            .onSubmit { addFolder() }
          
          Button {
            addFolder()
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(.green)
          }
          .buttonStyle(.borderless)
          .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      } header: {
        Text("Excluded Folders")
      } footer: {
        Text(
          "Files inside directories matching these names will be skipped during indexing."
        )
      }
      
      Section("Database information") {
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
            Text(
              "\(stats.enabledDirectories) of \(stats.totalDirectories) enabled"
            )
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
      
      Section(
        header: Text("Storage"),
        footer: Text(
          "Application data (local database, models, and thumbnails) is stored in this directory."
        )
      ) {
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
      
      Section("Logging") {
        Toggle(isOn: $debugMode) {
          Text("Debug mode")
          Text(
            "Log detailed profiling information such as search timing breakdowns."
          )
        }
        
        HStack {
          let logsURL = AppDatabase.dataDirectoryURL
            .appendingPathComponent("logs")
          Text(logsURL.path(percentEncoded: false))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          
          Spacer()
          
          Button("Open in Finder") {
            NSWorkspace.shared.open(logsURL)
          }
        }
      }
      
      Section("Reset") {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Reset All Warnings")
            Text(
              "Show confirmation dialogs that were previously dismissed with \"Don't show again.\""
            )
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
            Button("Cancel", role: .cancel) {}
          } message: {
            Text(
              "All previously suppressed confirmation dialogs will be shown again."
            )
          }
        }
        
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Reset View State")
            Text(
              "Restore dismissed views like the welcome screen so they appear again."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          
          Spacer()
          
          Button("Reset") {
            showResetViewStateConfirmation = true
          }
          .alert(
            "Reset View State?",
            isPresented: $showResetViewStateConfirmation
          ) {
            Button("Reset") {
              UserDefaults.standard.removeObject(
                forKey: StorageKey.hasSeenWelcome
              )
              NotificationCenter.default.post(
                name: .viewStateDidReset,
                object: nil
              )
            }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text(
              "Dismissed views such as the welcome screen will be shown again."
            )
          }
        }
      }
    }
    .formStyle(.grouped)
    .task {
      await refreshStats()
      loadExcludedFolders()
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
      LoggingService.shared.info(
        "Failed to fetch database stats: \(error)",
        category: "Settings"
      )
    }
  }
  
  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
  
  private func loadExcludedFolders() {
    guard
      let json = UserDefaults.standard.string(
        forKey: StorageKey.excludedFolderNames
      ),
      let data = json.data(using: .utf8),
      let array = try? JSONDecoder().decode([String].self, from: data)
    else {
      // First launch: populate with defaults
      excludedFolderNames = Self.defaultExcludedFolders
      saveExcludedFolders()
      return
    }
    excludedFolderNames = array
  }
  
  private func saveExcludedFolders() {
    if let data = try? JSONEncoder().encode(excludedFolderNames),
       let json = String(data: data, encoding: .utf8)
    {
      UserDefaults.standard.set(json, forKey: StorageKey.excludedFolderNames)
    }
  }
  
  private func addFolder() {
    let name = newFolderName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, !excludedFolderNames.contains(name) else { return }
    excludedFolderNames.append(name)
    saveExcludedFolders()
    newFolderName = ""
  }
  
  private func removeFolder(_ name: String) {
    excludedFolderNames.removeAll { $0 == name }
    saveExcludedFolders()
  }
}
