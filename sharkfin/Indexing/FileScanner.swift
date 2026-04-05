import Foundation
import CryptoKit

nonisolated struct QuickScannedFile: Sendable {
  let url: URL
  let filename: String
  let fileExtension: String
  let sizeBytes: Int64
  let modifiedAt: Date
}

nonisolated enum FileScanner {

  static let supportedExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "svg", "heic"
  ]

  /// Walk directory recursively and return all supported image files.
  /// This is a fast scan that only reads filesystem metadata (no file content hashing).
  static func scan(directory: URL) throws -> [QuickScannedFile] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    var results: [QuickScannedFile] = []

    for case let fileURL as URL in enumerator {
      let ext = fileURL.pathExtension.lowercased()
      guard supportedExtensions.contains(ext) else { continue }

      let resourceValues = try fileURL.resourceValues(
        forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
      )
      guard resourceValues.isRegularFile == true else { continue }

      results.append(QuickScannedFile(
        url: fileURL,
        filename: fileURL.lastPathComponent,
        fileExtension: ext,
        sizeBytes: Int64(resourceValues.fileSize ?? 0),
        modifiedAt: resourceValues.contentModificationDate ?? Date()
      ))
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
