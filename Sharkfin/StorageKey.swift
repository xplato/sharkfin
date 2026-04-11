import Foundation

/// Centralizes UserDefaults / @AppStorage key strings used across the app.
nonisolated enum StorageKey {
  static let hasSeenWelcome = "hasSeenWelcome"
  static let searchResultColumns = "searchResultColumns"
  static let excludedFolderNames = "excludedFolderNames"
  static let ignoreHiddenDirectories = "ignoreHiddenDirectories"
  static let debugMode = "debugMode"
  static let activeModelPackage = "activeModelPackage"
}
