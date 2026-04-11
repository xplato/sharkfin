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

// MARK: - Model File Specification

struct CLIPModelSpec: Identifiable {
  let id: String
  let displayName: String
  let repoID: String
  let files: [ModelFile]
  
  var totalSizeBytes: Int64 {
    files.reduce(0) { $0 + $1.sizeBytes }
  }
  
  func downloadURL(for file: ModelFile) -> URL {
    URL(
      string: "https://huggingface.co/\(repoID)/resolve/main/\(file.filename)"
    )!
  }
  
  struct ModelFile {
    let filename: String
    let sizeBytes: Int64
  }
}

// MARK: - Model Package

/// A paired set of CLIP text + vision encoders at a specific model size.
/// Each package produces embeddings of a fixed dimension and is identified
/// by a stable `id` that gets stored alongside embeddings in the database.
struct CLIPModelPackage: Identifiable {
  let id: String
  let displayName: String
  let description: String
  let embeddingDimension: Int
  let textEncoder: CLIPModelSpec
  let visionEncoder: CLIPModelSpec
  
  var totalSizeBytes: Int64 {
    textEncoder.totalSizeBytes + visionEncoder.totalSizeBytes
  }
  
  /// All individual model specs in this package.
  var specs: [CLIPModelSpec] { [textEncoder, visionEncoder] }
}

extension CLIPModelPackage {
  static let vitB32 = CLIPModelPackage(
    id: "clip-vit-base-patch32",
    displayName: "CLIP ViT-B/32",
    description: "Smallest and fastest. Good for general use.",
    embeddingDimension: 512,
    textEncoder: CLIPModelSpec(
      id: "clip-vit-base-patch32-text-onnx",
      displayName: "Text Encoder",
      repoID: "xplato/clip-vit-base-patch32-text-onnx",
      files: [
        .init(filename: "model.onnx", sizeBytes: 254_000_000),
        .init(filename: "tokenizer.json", sizeBytes: 2_220_000),
        .init(filename: "vocab.json", sizeBytes: 862_000),
        .init(filename: "merges.txt", sizeBytes: 525_000),
        .init(filename: "tokenizer_config.json", sizeBytes: 705),
        .init(filename: "special_tokens_map.json", sizeBytes: 588),
      ]
    ),
    visionEncoder: CLIPModelSpec(
      id: "clip-vit-base-patch32-vision-onnx",
      displayName: "Vision Encoder",
      repoID: "xplato/clip-vit-base-patch32-vision-onnx",
      files: [
        .init(filename: "model.onnx", sizeBytes: 352_000_000),
      ]
    )
  )
  
  static let vitB16 = CLIPModelPackage(
    id: "clip-vit-base-patch16",
    displayName: "CLIP ViT-B/16",
    description: "Better detail recognition, same download size.",
    embeddingDimension: 512,
    textEncoder: CLIPModelSpec(
      id: "clip-vit-base-patch16-text-onnx",
      displayName: "Text Encoder",
      repoID: "xplato/clip-vit-base-patch16-text-onnx",
      files: [
        .init(filename: "model.onnx", sizeBytes: 254_000_000),
        .init(filename: "tokenizer.json", sizeBytes: 2_220_000),
        .init(filename: "vocab.json", sizeBytes: 862_000),
        .init(filename: "merges.txt", sizeBytes: 525_000),
        .init(filename: "tokenizer_config.json", sizeBytes: 705),
        .init(filename: "special_tokens_map.json", sizeBytes: 588),
      ]
    ),
    visionEncoder: CLIPModelSpec(
      id: "clip-vit-base-patch16-vision-onnx",
      displayName: "Vision Encoder",
      repoID: "xplato/clip-vit-base-patch16-vision-onnx",
      files: [
        .init(filename: "model.onnx", sizeBytes: 345_000_000),
      ]
    )
  )
  
  static let vitL14 = CLIPModelPackage(
    id: "clip-vit-large-patch14",
    displayName: "CLIP ViT-L/14",
    description: "Best quality, larger download.",
    embeddingDimension: 768,
    textEncoder: CLIPModelSpec(
      id: "clip-vit-large-patch14-text-onnx",
      displayName: "Text Encoder",
      repoID: "xplato/clip-vit-large-patch14-text-onnx",
      files: [
        .init(filename: "model.onnx", sizeBytes: 495_000_000),
        .init(filename: "tokenizer.json", sizeBytes: 2_220_000),
        .init(filename: "vocab.json", sizeBytes: 862_000),
        .init(filename: "merges.txt", sizeBytes: 525_000),
        .init(filename: "tokenizer_config.json", sizeBytes: 705),
        .init(filename: "special_tokens_map.json", sizeBytes: 588),
      ]
    ),
    visionEncoder: CLIPModelSpec(
      id: "clip-vit-large-patch14-vision-onnx",
      displayName: "Vision Encoder",
      repoID: "xplato/clip-vit-large-patch14-vision-onnx",
      files: [
        .init(filename: "model.onnx", sizeBytes: 1_220_000_000),
      ]
    )
  )
  
  /// All available model packages, ordered from smallest to largest.
  static let all: [CLIPModelPackage] = [vitB32, vitB16, vitL14]
  
  /// The default package used when no preference has been set.
  static let `default` = vitB32
}

// MARK: - Model Manager

@MainActor
@Observable
final class CLIPModelManager {
  /// Download state for each individual model spec (keyed by spec ID).
  private(set) var modelStates: [String: ModelDownloadState] = [:]
  
  private var activeDownloads: [String: FileDownloader] = [:]
  private let fileManager = FileManager.default
  
  static let modelsDirectoryURL: URL = {
    AppDatabase.dataDirectoryURL.appendingPathComponent(
      "models",
      isDirectory: true
    )
  }()
  
  init() {
    self.activePackage = Self.loadActivePackage()
    try? fileManager.createDirectory(
      at: Self.modelsDirectoryURL,
      withIntermediateDirectories: true
    )
    cleanupTemporaryFiles()
    // Check download status for all specs across all packages
    for package in CLIPModelPackage.all {
      for spec in package.specs {
        modelStates[spec.id] = checkDownloadStatus(for: spec)
      }
    }
  }
  
  // MARK: - Active Package
  
  /// The user's selected model package. Stored so @Observable can track changes.
  private(set) var activePackage: CLIPModelPackage
  
  func setActivePackage(_ package: CLIPModelPackage) {
    activePackage = package
    UserDefaults.standard.set(package.id, forKey: StorageKey.activeModelPackage)
    NotificationCenter.default.post(
      name: .searchCacheDidInvalidate,
      object: nil
    )
  }
  
  private static func loadActivePackage() -> CLIPModelPackage {
    let storedId = UserDefaults.standard.string(
      forKey: StorageKey.activeModelPackage
    )
    return CLIPModelPackage.all.first { $0.id == storedId } ?? .default
  }
  
  // MARK: - Package-Level API
  
  /// Download all models in a package.
  func downloadPackage(_ package: CLIPModelPackage) {
    for spec in package.specs {
      download(spec)
    }
  }
  
  /// Cancel all downloads in a package.
  func cancelPackage(_ package: CLIPModelPackage) {
    for spec in package.specs {
      cancel(spec)
    }
  }
  
  /// Delete all model files in a package.
  func deletePackage(_ package: CLIPModelPackage) {
    for spec in package.specs {
      delete(spec)
    }
  }
  
  /// Whether all models in a package are downloaded and ready.
  func isPackageReady(_ package: CLIPModelPackage) -> Bool {
    package.specs.allSatisfy { modelStates[$0.id] == .downloaded }
  }
  
  /// Aggregate download state for a package.
  func packageState(_ package: CLIPModelPackage) -> ModelDownloadState {
    let states = package.specs.map { modelStates[$0.id] ?? .notDownloaded }
    if states.allSatisfy({ $0 == .downloaded }) { return .downloaded }
    if let error = states.first(where: {
      if case .error = $0 { return true }; return false
    }) { return error }
    // If any spec is downloading, compute aggregate progress
    let downloading = states.contains {
      if case .downloading = $0 { return true }; return false
    }
    if downloading {
      var totalBytes: Int64 = 0
      var weightedProgress: Double = 0
      for spec in package.specs {
        totalBytes += spec.totalSizeBytes
        if case .downloading(let p) = modelStates[spec.id] {
          weightedProgress += p * Double(spec.totalSizeBytes)
        } else if modelStates[spec.id] == .downloaded {
          weightedProgress += Double(spec.totalSizeBytes)
        }
      }
      let overall = totalBytes > 0 ? weightedProgress / Double(totalBytes) : 0
      return .downloading(progress: overall)
    }
    return .notDownloaded
  }
  
  // MARK: - Individual Spec API
  
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
  
  /// The text model URL for the active package, if downloaded.
  var textModelURL: URL? {
    let spec = activePackage.textEncoder
    guard modelStates[spec.id] == .downloaded else { return nil }
    return Self.modelsDirectoryURL
      .appendingPathComponent(spec.id)
      .appendingPathComponent("model.onnx")
  }
  
  /// The tokenizer folder URL for the active package, if downloaded.
  var textTokenizerFolderURL: URL? {
    let spec = activePackage.textEncoder
    guard modelStates[spec.id] == .downloaded else { return nil }
    return Self.modelsDirectoryURL.appendingPathComponent(spec.id)
  }
  
  /// The vision model URL for the active package, if downloaded.
  var visionModelURL: URL? {
    let spec = activePackage.visionEncoder
    guard modelStates[spec.id] == .downloaded else { return nil }
    return Self.modelsDirectoryURL
      .appendingPathComponent(spec.id)
      .appendingPathComponent("model.onnx")
  }
  
  /// Whether the active package is fully downloaded and ready.
  var isReady: Bool {
    isPackageReady(activePackage)
  }
  
  // MARK: - Download Logic
  
  private func performDownload(
    _ model: CLIPModelSpec,
    downloader: FileDownloader
  ) async {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)
    
    do {
      try fileManager.createDirectory(
        at: modelDir,
        withIntermediateDirectories: true
      )
    } catch {
      modelStates[model.id] = .error(
        "Failed to create directory: \(error.localizedDescription)"
      )
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
          self.modelStates[model.id] = .downloading(
            progress: min(overall, 0.99)
          )
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
  
  private func checkDownloadStatus(for model: CLIPModelSpec)
  -> ModelDownloadState
  {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)
    let allExist = model.files.allSatisfy { file in
      fileManager.fileExists(
        atPath: modelDir.appendingPathComponent(file.filename).path
      )
    }
    return allExist ? .downloaded : .notDownloaded
  }
  
  private func cleanupTemporaryFiles() {
    guard
      let enumerator = fileManager.enumerator(
        at: Self.modelsDirectoryURL,
        includingPropertiesForKeys: nil
      )
    else { return }
    for case let fileURL as URL in enumerator {
      if fileURL.pathExtension == "tmp" {
        try? fileManager.removeItem(at: fileURL)
      }
    }
  }
  
  private func cleanupPartialDownload(_ model: CLIPModelSpec) {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: modelDir,
        includingPropertiesForKeys: nil
      )
    else { return }
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
final class FileDownloader: NSObject, URLSessionDownloadDelegate,
                            @unchecked Sendable
{
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
    if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    {
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
