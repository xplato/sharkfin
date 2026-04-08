import AppKit

nonisolated enum ThumbnailError: Error {
  case cannotLoadImage
  case cannotEncode
}

nonisolated enum ThumbnailGenerator {
  
  static let thumbnailsDirectory: URL = {
    AppDatabase.dataDirectoryURL
      .appendingPathComponent("thumbnails", isDirectory: true)
  }()
  
  /// Generate a 256×256 max thumbnail. Uses PNG for images with transparency, JPEG otherwise.
  /// Skips generation if a thumbnail for this content hash already exists.
  static func generateThumbnail(for imageURL: URL, contentHash: String) throws
  -> String
  {
    let fm = FileManager.default
    try fm.createDirectory(
      at: thumbnailsDirectory,
      withIntermediateDirectories: true
    )
    
    // Check if either format already exists (content-addressed)
    let jpgURL = thumbnailsDirectory.appendingPathComponent(
      "\(contentHash).jpg"
    )
    let pngURL = thumbnailsDirectory.appendingPathComponent(
      "\(contentHash).png"
    )
    if fm.fileExists(atPath: pngURL.path) { return pngURL.path }
    if fm.fileExists(atPath: jpgURL.path) { return jpgURL.path }
    
    guard let image = NSImage(contentsOf: imageURL) else {
      throw ThumbnailError.cannotLoadImage
    }
    
    let size = image.size
    let maxDim: CGFloat = 256
    let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
    let newSize = NSSize(
      width: (size.width * scale).rounded(),
      height: (size.height * scale).rounded()
    )
    
    let thumbImage = NSImage(size: newSize)
    thumbImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: size),
      operation: .copy,
      fraction: 1.0
    )
    thumbImage.unlockFocus()
    
    guard let tiffData = thumbImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData)
    else {
      throw ThumbnailError.cannotEncode
    }
    
    // Use PNG if the image has alpha, JPEG otherwise
    let hasAlpha = bitmap.hasAlpha
    if hasAlpha {
      guard let pngData = bitmap.representation(using: .png, properties: [:])
      else {
        throw ThumbnailError.cannotEncode
      }
      try pngData.write(to: pngURL)
      return pngURL.path
    } else {
      guard
        let jpegData = bitmap.representation(
          using: .jpeg,
          properties: [.compressionFactor: 0.8]
        )
      else {
        throw ThumbnailError.cannotEncode
      }
      try jpegData.write(to: jpgURL)
      return jpgURL.path
    }
  }
}
