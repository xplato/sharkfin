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
    let home = FileManager.default.homeDirectoryForCurrentUser.path

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
