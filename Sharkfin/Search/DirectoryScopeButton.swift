import GRDB
import SwiftUI

struct DirectoryScopeButton: View {
  @Binding var scope: String?
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(\.colorScheme) private var colorScheme
  @State private var trees: [DirectoryTree] = []
  @State private var rebuildToken = 0
  
  private var isActive: Bool { scope != nil }
  
  private var buttonLabel: String {
    guard let scope else { return "Scope" }
    return URL(fileURLWithPath: scope).lastPathComponent
  }
  
  var body: some View {
    Menu {
      ForEach(trees) { tree in
        DirectoryNodeMenu(node: tree.root, scope: $scope)
      }
      
      if isActive {
        Divider()
        Button("Clear Scope") {
          scope = nil
        }
      }
    } label: {
      FilterButtonLabel(text: buttonLabel, isActive: isActive)
        .environment(\.colorScheme, isActive ? .dark : colorScheme)
    }
    .background(
      isActive
      ? AnyShapeStyle(Color.accentColor)
      : AnyShapeStyle(.clear),
      in: RoundedRectangle(cornerRadius: 6)
    )
    .fixedSize()
    .menuIndicator(.hidden)
    .task(
      id: TreeBuildID(
        dirIds: directoryStore.directories.map(\.id),
        token: rebuildToken
      )
    ) {
      trees = await buildTrees()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .searchCacheDidInvalidate)
    ) { _ in
      rebuildToken += 1
    }
  }
  
  private func buildTrees() async -> [DirectoryTree] {
    let dirs = directoryStore.directories.filter(\.enabled)
    let database = AppDatabase.shared
    return await Task.detached(priority: .userInitiated) {
      let indexedDirPaths = fetchIndexedDirectoryPaths(database: database)
      
      return await withTaskGroup(of: DirectoryTree?.self) { group in
        for dir in dirs {
          group.addTask {
            let label =
            dir.label
            ?? URL(fileURLWithPath: dir.path).lastPathComponent
            let children = enumerateChildren(
              at: dir.path,
              bookmark: dir.bookmark,
              depth: 0,
              indexedDirPaths: indexedDirPaths
            )
            return DirectoryTree(
              directoryId: dir.id ?? 0,
              root: DirectoryNode(
                name: label,
                path: dir.path,
                children: children
              )
            )
          }
        }
        var result: [DirectoryTree] = []
        for await tree in group {
          if let tree { result.append(tree) }
        }
        let idOrder = dirs.compactMap(\.id)
        result.sort { a, b in
          (idOrder.firstIndex(of: a.directoryId) ?? .max)
          < (idOrder.firstIndex(of: b.directoryId) ?? .max)
        }
        return result
      }
    }.value
  }
}

// MARK: - Tree data

private struct TreeBuildID: Equatable {
  let dirIds: [Int64?]
  let token: Int
}

private struct DirectoryTree: Identifiable {
  let directoryId: Int64
  let root: DirectoryNode
  var id: Int64 { directoryId }
}

private struct DirectoryNode: Identifiable {
  let name: String
  let path: String
  let children: [DirectoryNode]
  var id: String { path }
}

// MARK: - Recursive menu view (reads pre-built tree, no I/O)

private struct DirectoryNodeMenu: View {
  let node: DirectoryNode
  @Binding var scope: String?
  
  var body: some View {
    if node.children.isEmpty {
      Button {
        scope = node.path
      } label: {
        HStack {
          Text(node.name)
          Spacer()
          if scope == node.path {
            Image(systemName: "checkmark")
          }
        }
      }
    } else {
      Menu(node.name) {
        Button {
          scope = node.path
        } label: {
          HStack {
            Text("All of \(node.name)")
            Spacer()
            if scope == node.path {
              Image(systemName: "checkmark")
            }
          }
        }
        Divider()
        ForEach(node.children) { child in
          DirectoryNodeMenu(node: child, scope: $scope)
        }
      }
    }
  }
}

// MARK: - Indexed directory path lookup

/// Fetches all indexed file paths and returns the set of their ancestor
/// directory paths. Used to prune the scope menu to only directories that
/// actually contain indexed files.
nonisolated private func fetchIndexedDirectoryPaths(
  database: AppDatabase
) -> Set<String> {
  guard
    let paths = try? database.dbQueue.read({ db in
      try String.fetchAll(
        db,
        sql: """
          SELECT path FROM files
          WHERE directoryId IN (SELECT id FROM directories WHERE enabled = 1)
          """
      )
    })
  else { return [] }
  
  var dirPaths = Set<String>()
  for filePath in paths {
    var url = URL(fileURLWithPath: filePath)
    url.deleteLastPathComponent()
    while url.path.count > 1 {
      guard dirPaths.insert(url.path).inserted else { break }
      url.deleteLastPathComponent()
    }
  }
  return dirPaths
}

// MARK: - Async filesystem enumeration

nonisolated private let maxDepth = 4

nonisolated private func enumerateChildren(
  at path: String,
  bookmark: Data?,
  depth: Int,
  indexedDirPaths: Set<String>
) -> [DirectoryNode] {
  guard depth < maxDepth else { return [] }
  
  // Resolve bookmark once at the top level
  var accessURL: URL?
  if depth == 0, let bookmark {
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
  
  let url = URL(fileURLWithPath: path)
  let fm = FileManager.default
  guard
    let contents = try? fm.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
  else {
    return []
  }
  
  var nodes: [DirectoryNode] = []
  for item in contents {
    guard
      (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
        == true
    else { continue }
    // Only include directories that contain indexed files
    guard indexedDirPaths.contains(item.path) else { continue }
    let children = enumerateChildren(
      at: item.path,
      bookmark: nil,
      depth: depth + 1,
      indexedDirPaths: indexedDirPaths
    )
    nodes.append(
      DirectoryNode(
        name: item.lastPathComponent,
        path: item.path,
        children: children
      )
    )
  }
  nodes.sort {
    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
  }
  return nodes
}
