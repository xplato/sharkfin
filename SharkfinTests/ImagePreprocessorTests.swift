import AppKit
import Testing

@testable import Sharkfin

struct ImagePreprocessorTests {

  /// Creates a solid-color NSImage of the given size.
  nonisolated private func makeImage(width: Int, height: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
  }

  @Test func preprocessReturnsCorrectTensorSize() {
    let image = makeImage(width: 300, height: 300)
    let data = ImagePreprocessor.preprocess(image)
    #expect(data != nil)
    // 3 channels × 224 × 224 × sizeof(Float)
    #expect(data?.count == 3 * 224 * 224 * MemoryLayout<Float>.size)
  }

  @Test func preprocessHandlesPortraitImage() {
    let image = makeImage(width: 100, height: 400)
    let data = ImagePreprocessor.preprocess(image)
    #expect(data != nil)
    #expect(data?.count == 3 * 224 * 224 * MemoryLayout<Float>.size)
  }

  @Test func preprocessHandlesLandscapeImage() {
    let image = makeImage(width: 800, height: 200)
    let data = ImagePreprocessor.preprocess(image)
    #expect(data != nil)
    #expect(data?.count == 3 * 224 * 224 * MemoryLayout<Float>.size)
  }

  @Test func preprocessNormalizesPixelValues() {
    let image = makeImage(width: 224, height: 224)
    guard let data = ImagePreprocessor.preprocess(image) else {
      Issue.record("preprocess returned nil")
      return
    }
    let floats = data.withUnsafeBytes { buffer in
      Array(buffer.bindMemory(to: Float.self))
    }
    // After CLIP normalization, values should be in a small range, not raw 0-255
    let maxVal = floats.max() ?? 0
    let minVal = floats.min() ?? 0
    #expect(maxVal < 5)
    #expect(minVal > -5)
  }

  @Test func preprocessHandlesTinyImage() {
    let image = makeImage(width: 1, height: 1)
    let data = ImagePreprocessor.preprocess(image)
    #expect(data != nil)
    #expect(data?.count == 3 * 224 * 224 * MemoryLayout<Float>.size)
  }
}
