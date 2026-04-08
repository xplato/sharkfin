import Foundation

/// Holds all active search filter criteria.
///
/// Extensible — add new properties for future filter types
/// (e.g. directories, date range, file size).
struct SearchFilters: Equatable, Sendable {
  var fileTypes: Set<String>
  var directoryScope: String?
  
  nonisolated init(fileTypes: Set<String> = [], directoryScope: String? = nil) {
    self.fileTypes = fileTypes
    self.directoryScope = directoryScope
  }
  
  var isEmpty: Bool { fileTypes.isEmpty && directoryScope == nil }
}
