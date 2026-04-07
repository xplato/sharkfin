import SwiftUI

struct DirectoryScopeButton: View {
  @Binding var scope: String?
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(\.colorScheme) private var colorScheme
  @State private var trees: [DirectoryTree] = []

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
    .task(id: directoryStore.directories.map(\.id)) {
      trees = await buildTrees()
    }
  }

  private func buildTrees() async -> [DirectoryTree] {
    let dirs = directoryStore.directories.filter(\.enabled)
    return await Task.detached(priority: .userInitiated) {
      await withTaskGroup(of: DirectoryTree?.self) { group in
        for dir in dirs {
          group.addTask {
            let label =
              dir.label
              ?? URL(fileURLWithPath: dir.path).lastPathComponent
            let children = enumerateChildren(
              at: dir.path,
              bookmark: dir.bookmark,
              depth: 0
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

// MARK: - Async filesystem enumeration

nonisolated private let maxDepth = 4

nonisolated private func enumerateChildren(
  at path: String,
  bookmark: Data?,
  depth: Int
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
    let children = enumerateChildren(
      at: item.path,
      bookmark: nil,
      depth: depth + 1
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
