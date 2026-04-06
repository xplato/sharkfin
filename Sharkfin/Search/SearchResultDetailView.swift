import SwiftUI
import Quartz

struct SearchResultDetailView: View {
  let result: SearchResult
  @Environment(SearchController.self) private var searchController
  @State private var fileInfo: FileMetadataInfo?
  @State private var previewImage: NSImage?
  @State private var securityScopedURL: URL?

  var body: some View {
    VStack(spacing: 0) {
      detailToolbar

      ScrollView {
        HStack(alignment: .top, spacing: 16) {
          imagePreview
          metadataColumn
        }
        .padding(16)
      }
    }
    .task {
      await resolveSecurityScope()
      previewImage = Self.loadImage(
        at: result.path, fallbackThumbnail: result.thumbnailPath
      )
      fileInfo = FileMetadataInfo.load(from: result.path)
    }
    .onDisappear {
      securityScopedURL?.stopAccessingSecurityScopedResource()
    }
    .onKeyPress(.space) {
      quickLook()
      return .handled
    }
  }

  // MARK: - Toolbar

  private var detailToolbar: some View {
    HStack(spacing: 12) {
      Button { searchController.clearSelection() } label: {
        Image(systemName: "chevron.left")
          .font(.body.weight(.medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      Spacer()

      Button { quickLook() } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Quick Look")

      Button { revealInFinder() } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Reveal in Finder")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  // MARK: - Image Preview

  @ViewBuilder
  private var imagePreview: some View {
    if let image = previewImage {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(
          Color.primary.opacity(0.06),
          in: RoundedRectangle(cornerRadius: 8)
        )
        .frame(maxWidth: 260, maxHeight: 360)
        .onTapGesture { revealInFinder() }
        .help("Click to reveal in Finder")
    } else {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)
        .frame(width: 260, height: 200)
        .overlay {
          Image(systemName: "photo")
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
        }
    }
  }

  // MARK: - Metadata Column

  private var metadataColumn: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(result.filename)
        .font(.title3.weight(.medium))

      if let info = fileInfo {
        metadataTable(info)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func metadataTable(_ info: FileMetadataInfo) -> some View {
    VStack(spacing: 0) {
      if let type = info.fileType {
        metadataRow("Type", value: type)
        Divider()
      }
      if let resolution = info.resolution {
        metadataRow("Resolution", value: resolution)
        Divider()
      }
      metadataRow("Size", value: info.fileSize)
      Divider()
      metadataRow("Modified", value: info.modified)
      Divider()
      metadataRow("Created", value: info.created)
      Divider()
      HStack(alignment: .top) {
        Text("Path")
          .foregroundStyle(.secondary)
        Spacer()
        Text(result.path)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .truncationMode(.middle)
          .multilineTextAlignment(.trailing)
          .textSelection(.enabled)
      }
      .font(.callout)
      .padding(.vertical, 6)
    }
  }

  private func metadataRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .foregroundStyle(.primary)
    }
    .font(.callout)
    .padding(.vertical, 6)
  }

  // MARK: - Security Scope

  private func resolveSecurityScope() async {
    guard let bookmark = try? await AppDatabase.shared
      .directoryBookmark(forFileId: result.id) else { return }
    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmark,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else { return }
    if url.startAccessingSecurityScopedResource() {
      securityScopedURL = url
    }
  }

  // MARK: - Actions

  private func revealInFinder() {
    NSWorkspace.shared.selectFile(
      result.path, inFileViewerRootedAtPath: ""
    )
  }

  private func quickLook() {
    QuickLookHelper.shared.preview(
      url: URL(fileURLWithPath: result.path)
    )
  }

  // MARK: - Image Loading

  private static func loadImage(
    at path: String, fallbackThumbnail: String?
  ) -> NSImage? {
    if let image = NSImage(contentsOfFile: path) {
      return image
    }
    return fallbackThumbnail.flatMap { NSImage(contentsOfFile: $0) }
  }
}

// MARK: - File Metadata

private struct FileMetadataInfo {
  let fileType: String?
  let fileSize: String
  let resolution: String?
  let modified: String
  let created: String

  static func load(from path: String) -> FileMetadataInfo? {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: path) else {
      return nil
    }

    let url = URL(fileURLWithPath: path)

    let ext = url.pathExtension
    let fileType = ext.isEmpty ? nil : ext.uppercased()

    let bytes = (attrs[.size] as? Int64) ?? 0
    let fileSize = ByteCountFormatter.string(
      fromByteCount: bytes, countStyle: .file
    )

    var resolution: String? = nil
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(
         source, 0, nil
       ) as? [String: Any],
       let w = props[kCGImagePropertyPixelWidth as String] as? Int,
       let h = props[kCGImagePropertyPixelHeight as String] as? Int {
      resolution = "\(w) × \(h)"
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    let modified = (attrs[.modificationDate] as? Date)
      .map { formatter.string(from: $0) } ?? "—"
    let created = (attrs[.creationDate] as? Date)
      .map { formatter.string(from: $0) } ?? "—"

    return FileMetadataInfo(
      fileType: fileType,
      fileSize: fileSize,
      resolution: resolution,
      modified: modified,
      created: created
    )
  }
}

// MARK: - Quick Look Helper

final class QuickLookHelper: NSObject, QLPreviewPanelDataSource,
  @unchecked Sendable
{
  @MainActor static let shared = QuickLookHelper()

  nonisolated(unsafe) private var previewURL: NSURL?

  @MainActor
  func preview(url: URL) {
    previewURL = url as NSURL
    guard let panel = QLPreviewPanel.shared() else { return }
    panel.dataSource = self
    if panel.isVisible {
      panel.reloadData()
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    previewURL != nil ? 1 : 0
  }

  func previewPanel(
    _ panel: QLPreviewPanel!,
    previewItemAt index: Int
  ) -> (any QLPreviewItem)! {
    previewURL
  }
}
