import Foundation

/// Holds all active search filter criteria.
///
/// Extensible — add new properties for future filter types
/// (e.g. directories, date range, file size).
struct SearchFilters: Equatable, Sendable {
  var fileTypes: Set<String>

  nonisolated init(fileTypes: Set<String> = []) {
    self.fileTypes = fileTypes
  }

  var isEmpty: Bool { fileTypes.isEmpty }
}
