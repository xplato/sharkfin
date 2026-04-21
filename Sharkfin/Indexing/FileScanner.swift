import CryptoKit
import Foundation

nonisolated struct QuickScannedFile: Sendable {
  let url: URL
  let filename: String
  let fileExtension: String
  let sizeBytes: Int64
  let modifiedAt: Date
  /// The file's inode number, used to detect renames without re-indexing.
  let fileIdentifier: Int64?
}

nonisolated enum FileScanner {
  
  static let supportedExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "svg", "heic",
  ]
  
  /// Walk directory recursively and return all supported image files.
  /// This is a fast scan that only reads filesystem metadata (no file content hashing).
  static func scan(
    directory: URL,
    skipHiddenFiles: Bool = true,
    excludedFolderNames: Set<String> = []
  ) throws -> [QuickScannedFile] {
    let fm = FileManager.default
    var options: FileManager.DirectoryEnumerationOptions = []
    if skipHiddenFiles {
      options.insert(.skipsHiddenFiles)
    }
    guard
      let enumerator = fm.enumerator(
        at: directory,
        includingPropertiesForKeys: [
          .fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
        ],
        options: options
      )
    else { return [] }
    
    let directoryPath = directory.standardizedFileURL.path(
      percentEncoded: false
    )
    var results: [QuickScannedFile] = []
    
    for case let fileURL as URL in enumerator {
      // Check if any path component after the base directory matches an excluded folder name
      if !excludedFolderNames.isEmpty {
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
        let relativePath = String(filePath.dropFirst(directoryPath.count))
        let components = relativePath.split(separator: "/").dropLast()  // drop the filename
        if components.contains(where: {
          excludedFolderNames.contains(String($0))
        }) {
          continue
        }
      }
      
      let ext = fileURL.pathExtension.lowercased()
      guard supportedExtensions.contains(ext) else { continue }
      
      let resourceValues = try fileURL.resourceValues(
        forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
      )
      guard resourceValues.isRegularFile == true else { continue }
      
      // Capture the inode so we can detect renames without re-indexing.
      var statInfo = stat()
      let inode: Int64? =
      stat(fileURL.path, &statInfo) == 0 ? Int64(statInfo.st_ino) : nil
      
      results.append(
        QuickScannedFile(
          url: fileURL,
          filename: fileURL.lastPathComponent,
          fileExtension: ext,
          sizeBytes: Int64(resourceValues.fileSize ?? 0),
          modifiedAt: resourceValues.contentModificationDate ?? Date(),
          fileIdentifier: inode
        )
      )
    }
    
    return results
  }
  
  /// SHA256 hash of file contents as lowercase hex string.
  static func hashFile(at url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
