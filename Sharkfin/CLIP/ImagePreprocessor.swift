import AppKit

/// Converts NSImage to the [1, 3, 224, 224] CHW float tensor that CLIP expects.
nonisolated enum ImagePreprocessor {

  private static let imageSize = 224
  private static let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
  private static let std: [Float] = [0.26862954, 0.26130258, 0.27577711]

  static func preprocess(_ image: NSImage) -> Data? {
    guard
      let cgImage = image.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
      )
    else {
      return nil
    }

    // Resize shortest side to 224, preserving aspect ratio
    let (width, height) = (cgImage.width, cgImage.height)
    let scale = 224.0 / Double(min(width, height))
    let newW = Int((Double(width) * scale).rounded())
    let newH = Int((Double(height) * scale).rounded())

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Draw resized image
    guard
      let resizeCtx = CGContext(
        data: nil,
        width: newW,
        height: newH,
        bitsPerComponent: 8,
        bytesPerRow: newW * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else { return nil }

    resizeCtx.interpolationQuality = .high
    // Fill white background (important for transparent images / SVGs)
    resizeCtx.setFillColor(.white)
    resizeCtx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
    resizeCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))

    guard let resizedImage = resizeCtx.makeImage() else { return nil }

    // Center crop to 224×224
    let cropX = (newW - imageSize) / 2
    let cropY = (newH - imageSize) / 2
    guard
      let croppedImage = resizedImage.cropping(
        to: CGRect(x: cropX, y: cropY, width: imageSize, height: imageSize)
      )
    else { return nil }

    // Extract RGBA pixels
    guard
      let pixelCtx = CGContext(
        data: nil,
        width: imageSize,
        height: imageSize,
        bitsPerComponent: 8,
        bytesPerRow: imageSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else { return nil }

    pixelCtx.draw(
      croppedImage,
      in: CGRect(x: 0, y: 0, width: imageSize, height: imageSize)
    )

    guard let pixelData = pixelCtx.data else { return nil }
    let pixels = pixelData.bindMemory(
      to: UInt8.self,
      capacity: imageSize * imageSize * 4
    )

    // Build CHW tensor: [1, 3, 224, 224] = 150528 floats
    let pixelCount = imageSize * imageSize
    var tensor = [Float](repeating: 0, count: 3 * pixelCount)

    for i in 0..<pixelCount {
      let r = Float(pixels[i * 4 + 0]) / 255.0
      let g = Float(pixels[i * 4 + 1]) / 255.0
      let b = Float(pixels[i * 4 + 2]) / 255.0

      tensor[0 * pixelCount + i] = (r - mean[0]) / std[0]
      tensor[1 * pixelCount + i] = (g - mean[1]) / std[1]
      tensor[2 * pixelCount + i] = (b - mean[2]) / std[2]
    }

    return tensor.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}
