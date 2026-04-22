import SwiftUI

// MARK: - Context Menu Modifier

struct SearchResultContextMenu: ViewModifier {
  let result: SearchResult
  @Environment(SearchController.self) private var searchController
  
  
  func body(content: Content) -> some View {
    content.contextMenu {
      Button("Open") {
        openFile()
      }
      
      openWithMenu
      
      Divider()
      
      Button("Reveal in Finder") {
        revealInFinder()
      }
      
      Divider()
      
      Button("Copy Image") {
        copyImage()
      }
      
      Button("Copy Path") {
        copyPath()
      }
      
      Divider()
      
      Button("Share...") {
        shareFile()
      }
      
      Divider()
      
      Button("Move to Trash", role: .destructive) {
        performTrash()
      }
    }
  }
  
  // MARK: - Open With Submenu
  
  @ViewBuilder
  private var openWithMenu: some View {
    let fileURL = URL(fileURLWithPath: result.path)
    let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
    if !appURLs.isEmpty {
      Menu("Open With") {
        ForEach(appURLs, id: \.self) { appURL in
          Button {
            openWith(appURL: appURL)
          } label: {
            Label {
              Text(appURL.deletingPathExtension().lastPathComponent)
            } icon: {
              Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 12, height: 12)
            }
          }
        }
      }
    }
  }
  
  // MARK: - Actions
  
  private func openFile() {
    withScopedAccess {
      NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
    }
  }
  
  private func openWith(appURL: URL) {
    withScopedAccess {
      NSWorkspace.shared.open(
        [URL(fileURLWithPath: result.path)],
        withApplicationAt: appURL,
        configuration: NSWorkspace.OpenConfiguration()
      )
    }
  }
  
  private func revealInFinder() {
    withScopedAccess {
      NSWorkspace.shared.selectFile(
        result.path,
        inFileViewerRootedAtPath: ""
      )
    }
  }
  
  private func copyImage() {
    withScopedAccess {
      guard let image = NSImage(contentsOfFile: result.path) else { return }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([image])
    }
  }
  
  private func copyPath() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(result.path, forType: .string)
  }
  
  private func shareFile() {
    withScopedAccess {
      guard let image = NSImage(contentsOfFile: result.path) else { return }
      let picker = NSSharingServicePicker(items: [image])
      guard let contentView = NSApp.keyWindow?.contentView else { return }
      // Show from the center of the window; the context menu is already dismissed
      let point = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
      picker.show(relativeTo: CGRect(origin: point, size: .zero),
                  of: contentView, preferredEdge: .minY)
    }
  }
  
  private func performTrash() {
    let fileId = result.id
    let filePath = result.path
    let controller = searchController
    
    withScopedAccess {
      let fileURL = URL(fileURLWithPath: filePath)
      do {
        try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
        NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif", byReference: true)?.play()
        Task { @MainActor in
          controller.onRemoveResult?(fileId)
        }
      } catch {
        LoggingService.shared.info(
          "Failed to trash file: \(error.localizedDescription)",
          category: "ContextMenu"
        )
      }
    }
  }
  
  // MARK: - Security-Scoped Access
  
  private func withScopedAccess(perform action: @escaping @Sendable () -> Void) {
    Task {
      guard let bookmark = try? await AppDatabase.shared
        .directoryBookmark(forFileId: result.id) else {
        action()
        return
      }
      var isStale = false
      guard let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), url.startAccessingSecurityScopedResource() else {
        action()
        return
      }
      defer { url.stopAccessingSecurityScopedResource() }
      action()
    }
  }
}

extension View {
  func searchResultContextMenu(_ result: SearchResult) -> some View {
    modifier(SearchResultContextMenu(result: result))
  }
}
