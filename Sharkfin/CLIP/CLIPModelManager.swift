// TODO: rebuild this whole thing smh

import Foundation
import Observation

// MARK: - Model Download State

enum ModelDownloadState: Equatable {
  case notDownloaded
  case downloading(progress: Double)
  case downloaded
  case error(String)
}

// MARK: - Model Specification

struct CLIPModelSpec: Identifiable {
  let id: String
  let displayName: String
  let repoID: String
  let files: [ModelFile]

  var totalSizeBytes: Int64 {
    files.reduce(0) { $0 + $1.sizeBytes }
  }

  func downloadURL(for file: ModelFile) -> URL {
    URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(file.filename)")!
  }

  struct ModelFile {
    let filename: String
    let sizeBytes: Int64
  }
}

extension CLIPModelSpec {
  static let textEncoder = CLIPModelSpec(
    id: "clip-vit-base-patch32-text-onnx",
    displayName: "CLIP Text Encoder",
    repoID: "xplato/clip-vit-base-patch32-text-onnx",
    files: [
      ModelFile(filename: "model.onnx", sizeBytes: 254_000_000),
      ModelFile(filename: "tokenizer.json", sizeBytes: 2_220_000),
      ModelFile(filename: "vocab.json", sizeBytes: 862_000),
      ModelFile(filename: "merges.txt", sizeBytes: 525_000),
      ModelFile(filename: "config.json", sizeBytes: 536),
      ModelFile(filename: "tokenizer_config.json", sizeBytes: 705),
      ModelFile(filename: "special_tokens_map.json", sizeBytes: 588),
    ]
  )

  static let visionEncoder = CLIPModelSpec(
    id: "clip-vit-base-patch32-vision-onnx",
    displayName: "CLIP Vision Encoder",
    repoID: "xplato/clip-vit-base-patch32-vision-onnx",
    files: [
      ModelFile(filename: "model.onnx", sizeBytes: 352_000_000),
      ModelFile(filename: "config.json", sizeBytes: 482),
      ModelFile(filename: "preprocessor_config.json", sizeBytes: 780),
    ]
  )

  static let all: [CLIPModelSpec] = [textEncoder, visionEncoder]
}

// MARK: - Model Manager

@MainActor
@Observable
final class CLIPModelManager {
  private(set) var modelStates: [String: ModelDownloadState] = [:]

  private var activeDownloads: [String: FileDownloader] = [:]
  private let fileManager = FileManager.default

  static let modelsDirectoryURL: URL = {
    AppDatabase.dataDirectoryURL.appendingPathComponent("models", isDirectory: true)
  }()

  init() {
    try? fileManager.createDirectory(
      at: Self.modelsDirectoryURL,
      withIntermediateDirectories: true
    )
    cleanupTemporaryFiles()
    for model in CLIPModelSpec.all {
      modelStates[model.id] = checkDownloadStatus(for: model)
    }
  }

  // MARK: - Public API

  func download(_ model: CLIPModelSpec) {
    guard modelStates[model.id] != .downloading(progress: 0) else { return }
    modelStates[model.id] = .downloading(progress: 0)

    let downloader = FileDownloader()
    activeDownloads[model.id] = downloader

    Task {
      await performDownload(model, downloader: downloader)
    }
  }

  func cancel(_ model: CLIPModelSpec) {
    activeDownloads[model.id]?.cancelAll()
    activeDownloads[model.id] = nil
    cleanupPartialDownload(model)
    modelStates[model.id] = .notDownloaded
  }

  func delete(_ model: CLIPModelSpec) {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)
    try? fileManager.removeItem(at: modelDir)
    modelStates[model.id] = .notDownloaded
  }

  func retry(_ model: CLIPModelSpec) {
    download(model)
  }

  // MARK: - Convenience Accessors

  var textModelURL: URL? {
    guard modelStates[CLIPModelSpec.textEncoder.id] == .downloaded else { return nil }
    return Self.modelsDirectoryURL
      .appendingPathComponent(CLIPModelSpec.textEncoder.id)
      .appendingPathComponent("model.onnx")
  }

  var textTokenizerFolderURL: URL? {
    guard modelStates[CLIPModelSpec.textEncoder.id] == .downloaded else { return nil }
    return Self.modelsDirectoryURL
      .appendingPathComponent(CLIPModelSpec.textEncoder.id)
  }

  var visionModelURL: URL? {
    guard modelStates[CLIPModelSpec.visionEncoder.id] == .downloaded else { return nil }
    return Self.modelsDirectoryURL
      .appendingPathComponent(CLIPModelSpec.visionEncoder.id)
      .appendingPathComponent("model.onnx")
  }

  var isReady: Bool {
    modelStates[CLIPModelSpec.textEncoder.id] == .downloaded &&
    modelStates[CLIPModelSpec.visionEncoder.id] == .downloaded
  }

  // MARK: - Download Logic

  private func performDownload(_ model: CLIPModelSpec, downloader: FileDownloader) async {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)

    do {
      try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
    } catch {
      modelStates[model.id] = .error("Failed to create directory: \(error.localizedDescription)")
      return
    }

    let totalBytes = model.totalSizeBytes
    var completedBytes: Int64 = 0

    for file in model.files {
      let destinationURL = modelDir.appendingPathComponent(file.filename)

      // Skip already-downloaded files (enables resume after partial failure)
      if fileManager.fileExists(atPath: destinationURL.path) {
        completedBytes += file.sizeBytes
        modelStates[model.id] = .downloading(
          progress: Double(completedBytes) / Double(totalBytes)
        )
        continue
      }

      let baseBytes = completedBytes
      let result = await downloader.download(
        from: model.downloadURL(for: file),
        to: destinationURL
      ) { [weak self] fileProgress in
        guard let self else { return }
        let bytesForFile = Int64(fileProgress * Double(file.sizeBytes))
        let overall = Double(baseBytes + bytesForFile) / Double(totalBytes)
        Task { @MainActor in
          self.modelStates[model.id] = .downloading(progress: min(overall, 0.99))
        }
      }

      switch result {
      case .success:
        completedBytes += file.sizeBytes
        modelStates[model.id] = .downloading(
          progress: Double(completedBytes) / Double(totalBytes)
        )
      case .cancelled:
        return
      case .failure(let message):
        modelStates[model.id] = .error(message)
        activeDownloads[model.id] = nil
        return
      }
    }

    modelStates[model.id] = .downloaded
    activeDownloads[model.id] = nil
  }

  // MARK: - File Management

  private func checkDownloadStatus(for model: CLIPModelSpec) -> ModelDownloadState {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)
    let allExist = model.files.allSatisfy { file in
      fileManager.fileExists(atPath: modelDir.appendingPathComponent(file.filename).path)
    }
    return allExist ? .downloaded : .notDownloaded
  }

  private func cleanupTemporaryFiles() {
    guard let enumerator = fileManager.enumerator(
      at: Self.modelsDirectoryURL,
      includingPropertiesForKeys: nil
    ) else { return }
    for case let fileURL as URL in enumerator {
      if fileURL.pathExtension == "tmp" {
        try? fileManager.removeItem(at: fileURL)
      }
    }
  }

  private func cleanupPartialDownload(_ model: CLIPModelSpec) {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)
    guard let contents = try? fileManager.contentsOfDirectory(
      at: modelDir,
      includingPropertiesForKeys: nil
    ) else { return }
    for fileURL in contents where fileURL.pathExtension == "tmp" {
      try? fileManager.removeItem(at: fileURL)
    }
  }
}

// MARK: - Download Result

enum DownloadResult {
  case success
  case cancelled
  case failure(String)
}

// MARK: - File Downloader (URLSessionDownloadDelegate)

/// Handles individual file downloads with progress reporting, automatic retry
/// with resume data, and timeouts suitable for large model files.
/// The HuggingFace Xet CDN tends to drop connections on large files, so we
/// retry aggressively with resume data to incrementally complete the download.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private var continuation: CheckedContinuation<DownloadResult, Never>?
  private var progressHandler: ((Double) -> Void)?
  private var destinationURL: URL?
  private var activeTask: URLSessionDownloadTask?
  private var resumeData: Data?
  private var isCancelled = false
  private var consecutiveResumeFails = 0

  private static let maxRetries = 15

  /// Create a fresh ephemeral session for each download attempt to avoid
  /// stale HTTP/2 connection reuse that triggers -1005 on the CDN.
  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 7200
    config.waitsForConnectivity = true
    config.httpMaximumConnectionsPerHost = 1
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

  func download(
    from url: URL,
    to destination: URL,
    progress: @escaping (Double) -> Void
  ) async -> DownloadResult {
    self.destinationURL = destination
    self.progressHandler = progress
    self.isCancelled = false
    self.resumeData = nil
    self.consecutiveResumeFails = 0

    var lastResult: DownloadResult = .failure("Download did not start")

    for attempt in 0..<Self.maxRetries {
      if isCancelled { return .cancelled }

      if attempt > 0 {
        let delay = min(2 + attempt, 10)
        try? await Task.sleep(for: .seconds(delay))
        if isCancelled { return .cancelled }
      }

      // Fresh session per attempt avoids stale connection issues
      let session = makeSession()

      lastResult = await withCheckedContinuation { continuation in
        self.continuation = continuation

        let task: URLSessionDownloadTask
        if let data = self.resumeData, self.consecutiveResumeFails < 2 {
          task = session.downloadTask(withResumeData: data)
        } else {
          // Resume data expired or failed twice — start fresh from original URL
          // which will get a new signed CDN redirect
          self.resumeData = nil
          self.consecutiveResumeFails = 0
          task = session.downloadTask(with: url)
        }
        self.activeTask = task
        task.resume()
      }

      session.invalidateAndCancel()

      switch lastResult {
      case .success, .cancelled:
        return lastResult
      case .failure:
        continue
      }
    }

    return lastResult
  }

  func cancelAll() {
    isCancelled = true
    activeTask?.cancel()
    activeTask = nil
  }

  // MARK: - URLSessionDownloadDelegate

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let destination = destinationURL else {
      continuation?.resume(returning: .failure("No destination URL set"))
      continuation = nil
      return
    }

    do {
      let fm = FileManager.default
      if fm.fileExists(atPath: destination.path) {
        try fm.removeItem(at: destination)
      }
      try fm.moveItem(at: location, to: destination)
      continuation?.resume(returning: .success)
      continuation = nil
    } catch {
      continuation?.resume(returning: .failure(error.localizedDescription))
      continuation = nil
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    progressHandler?(fraction)
  }

  nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let error else { return }

    let nsError = error as NSError

    // Capture resume data for retry
    if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
      self.resumeData = data
      self.consecutiveResumeFails = 0
    } else if self.resumeData != nil {
      // Had resume data but this attempt didn't produce new data — likely expired
      self.consecutiveResumeFails += 1
    }

    if nsError.code == NSURLErrorCancelled && isCancelled {
      continuation?.resume(returning: .cancelled)
    } else {
      continuation?.resume(returning: .failure(error.localizedDescription))
    }
    continuation = nil
  }
}
