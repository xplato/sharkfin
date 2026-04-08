import Foundation

/// Centralizes UserDefaults / @AppStorage key strings used across the app.
nonisolated enum StorageKey {
  static let hasSeenWelcome = "hasSeenWelcome"
  static let preserveSearchFilter = "preserveSearchFilter"
  static let searchResultColumns = "searchResultColumns"
  static let watchDirectories = "watchDirectories"
  static let indexOnLaunch = "indexOnLaunch"
  static let excludedFolderNames = "excludedFolderNames"
  static let ignoreHiddenDirectories = "ignoreHiddenDirectories"
  static let debugMode = "debugMode"
}
