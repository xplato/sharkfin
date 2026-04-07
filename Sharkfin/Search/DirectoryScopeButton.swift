import SwiftUI

struct DirectoryScopeButton: View {
  @Binding var scope: String?
  @Environment(DirectoryStore.self) private var directoryStore
  
  private var isActive: Bool { scope != nil }
  
  private var buttonLabel: String {
    guard let scope else { return "Scope" }
    return URL(fileURLWithPath: scope).lastPathComponent
  }
  
  var body: some View {
    Menu {
      let enabledDirs = directoryStore.directories.filter(\.enabled)
      ForEach(enabledDirs) { directory in
        DirectorySubmenu(
          path: directory.path,
          label: directory.label ?? URL(fileURLWithPath: directory.path).lastPathComponent,
          bookmark: directory.bookmark,
          scope: $scope
        )
      }
      
      if isActive {
        Divider()
        Button("Clear Scope") {
          scope = nil
        }
      }
    } label: {
      Text(buttonLabel)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(isActive ? .white : .secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .background(
      isActive
      ? AnyShapeStyle(Color.accentColor)
      : AnyShapeStyle(.clear),
      in: RoundedRectangle(cornerRadius: 6)
    )
    .fixedSize()
    .menuIndicator(.hidden)
    .simultaneousGesture(
      TapGesture().modifiers(.command).onEnded {
        scope = nil
      }
    )
  }
}

// MARK: - Recursive submenu for directory tree

private struct DirectorySubmenu: View {
  let path: String
  let label: String
  let bookmark: Data?
  @Binding var scope: String?
  
  var body: some View {
    let subdirs = listSubdirectories(at: path, bookmark: bookmark)
    if subdirs.isEmpty {
      Button {
        scope = path
      } label: {
        HStack {
          Text(label)
          Spacer()
          if scope == path {
            Image(systemName: "checkmark")
          }
        }
      }
    } else {
      Menu(label) {
        Button {
          scope = path
        } label: {
          HStack {
            Text("All of \(label)")
            Spacer()
            if scope == path {
              Image(systemName: "checkmark")
            }
          }
        }
        Divider()
        ForEach(subdirs, id: \.path) { subdir in
          DirectorySubmenu(
            path: subdir.path,
            label: subdir.name,
            bookmark: bookmark,
            scope: $scope
          )
        }
      }
    }
  }
}

// MARK: - Filesystem helpers

private struct SubdirectoryEntry: Hashable {
  let name: String
  let path: String
}

private func listSubdirectories(at path: String, bookmark: Data?) -> [SubdirectoryEntry] {
  let url = URL(fileURLWithPath: path)
  
  // Resolve security-scoped bookmark if available
  var accessURL: URL?
  if let bookmark {
    var isStale = false
    if let resolved = try? URL(
      resolvingBookmarkData: bookmark,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) {
      if resolved.startAccessingSecurityScopedResource() {
        accessURL = resolved
      }
    }
  }
  defer { accessURL?.stopAccessingSecurityScopedResource() }
  
  let fm = FileManager.default
  guard let contents = try? fm.contentsOfDirectory(
    at: url,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }
  
  return contents
    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    .map { SubdirectoryEntry(name: $0.lastPathComponent, path: $0.path) }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
