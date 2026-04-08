import Foundation

/// Formats a file path for user-facing display by stripping common
/// prefixes that add visual noise without useful information.
///
/// - iCloud Drive paths have the
///   `/Users/<user>/Library/Mobile Documents/com~apple~CloudDocs/` prefix
///   replaced with `iCloud Drive/`.
/// - All other paths under `/Users/<user>/` have that prefix stripped.
/// - Paths that don't match either pattern are returned unchanged.
func formatDisplayPath(_ path: String) -> String {
  // Use getpwuid to get the real home directory, since
  // FileManager.homeDirectoryForCurrentUser returns the sandbox
  // container path in sandboxed apps.
  let home: String
  if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
    home = String(cString: dir)
  } else {
    home = FileManager.default.homeDirectoryForCurrentUser.path
  }
  
  let iCloudSuffix = "/Library/Mobile Documents/com~apple~CloudDocs/"
  let iCloudPrefix = home + iCloudSuffix
  
  if path.hasPrefix(iCloudPrefix) {
    return "iCloud Drive/" + String(path.dropFirst(iCloudPrefix.count))
  }
  
  let homeSlash = home.hasSuffix("/") ? home : home + "/"
  if path.hasPrefix(homeSlash) {
    return String(path.dropFirst(homeSlash.count))
  }
  
  return path
}
