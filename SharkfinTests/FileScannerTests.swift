import Foundation
import Testing

@testable import Sharkfin

struct FileScannerTests {
  
  /// Creates a temporary directory that is cleaned up after the test.
  private func withTempDirectory(
    _ body: (URL) throws -> Void
  ) throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try body(tempDir)
  }
  
  // MARK: - Supported extensions
  
  @Test func supportedExtensionsContainsCommonFormats() {
    #expect(FileScanner.supportedExtensions.contains("jpg"))
    #expect(FileScanner.supportedExtensions.contains("jpeg"))
    #expect(FileScanner.supportedExtensions.contains("png"))
    #expect(FileScanner.supportedExtensions.contains("gif"))
    #expect(FileScanner.supportedExtensions.contains("webp"))
    #expect(FileScanner.supportedExtensions.contains("heic"))
  }
  
  @Test func supportedExtensionsExcludesNonImageFormats() {
    #expect(!FileScanner.supportedExtensions.contains("txt"))
    #expect(!FileScanner.supportedExtensions.contains("pdf"))
    #expect(!FileScanner.supportedExtensions.contains("mp4"))
  }
  
  // MARK: - hashFile
  
  @Test func hashFileProducesDeterministicSHA256() throws {
    try withTempDirectory { tempDir in
      let fileURL = tempDir.appendingPathComponent("test.txt")
      try Data("hello".utf8).write(to: fileURL)
      
      let hash1 = try FileScanner.hashFile(at: fileURL)
      let hash2 = try FileScanner.hashFile(at: fileURL)
      #expect(hash1 == hash2)
      #expect(
        hash1
        == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
      )
    }
  }
  
  @Test func hashFileDiffersForDifferentContent() throws {
    try withTempDirectory { tempDir in
      let file1 = tempDir.appendingPathComponent("a.txt")
      let file2 = tempDir.appendingPathComponent("b.txt")
      try Data("content1".utf8).write(to: file1)
      try Data("content2".utf8).write(to: file2)
      
      let h1 = try FileScanner.hashFile(at: file1)
      let h2 = try FileScanner.hashFile(at: file2)
      #expect(h1 != h2)
    }
  }
  
  // MARK: - scan
  
  @Test func scanFindsImageFilesRecursively() throws {
    try withTempDirectory { tempDir in
      let subDir = tempDir.appendingPathComponent("subfolder")
      try FileManager.default.createDirectory(
        at: subDir,
        withIntermediateDirectories: true
      )
      
      try Data("img".utf8).write(
        to: tempDir.appendingPathComponent("photo.jpg")
      )
      try Data("img".utf8).write(
        to: subDir.appendingPathComponent("deep.png")
      )
      try Data("txt".utf8).write(
        to: tempDir.appendingPathComponent("readme.txt")
      )
      
      let results = try FileScanner.scan(directory: tempDir)
      let filenames = results.map(\.filename)
      #expect(filenames.contains("photo.jpg"))
      #expect(filenames.contains("deep.png"))
      #expect(!filenames.contains("readme.txt"))
    }
  }
  
  @Test func scanSkipsHiddenFiles() throws {
    try withTempDirectory { tempDir in
      try Data("img".utf8).write(
        to: tempDir.appendingPathComponent(".hidden.jpg")
      )
      try Data("img".utf8).write(
        to: tempDir.appendingPathComponent("visible.jpg")
      )
      
      let results = try FileScanner.scan(
        directory: tempDir,
        skipHiddenFiles: true
      )
      #expect(results.count == 1)
      #expect(results.first?.filename == "visible.jpg")
    }
  }
  
  @Test func scanRespectsExcludedFolderNames() throws {
    try withTempDirectory { tempDir in
      let excluded = tempDir.appendingPathComponent("node_modules")
      try FileManager.default.createDirectory(
        at: excluded,
        withIntermediateDirectories: true
      )
      
      try Data("img".utf8).write(
        to: excluded.appendingPathComponent("junk.jpg")
      )
      try Data("img".utf8).write(
        to: tempDir.appendingPathComponent("keep.jpg")
      )
      
      let results = try FileScanner.scan(
        directory: tempDir,
        excludedFolderNames: ["node_modules"]
      )
      #expect(results.count == 1)
      #expect(results.first?.filename == "keep.jpg")
    }
  }
  
  @Test func scanReturnsCorrectMetadata() throws {
    try withTempDirectory { tempDir in
      let data = Data(repeating: 0xFF, count: 1024)
      try data.write(to: tempDir.appendingPathComponent("test.jpeg"))
      
      let results = try FileScanner.scan(directory: tempDir)
      #expect(results.count == 1)
      let file = results[0]
      #expect(file.filename == "test.jpeg")
      #expect(file.fileExtension == "jpeg")
      #expect(file.sizeBytes == 1024)
    }
  }
}
