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
    repoID: "kjsdu2/clip-vit-base-patch32-text-onnx",
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
    repoID: "kjsdu2/clip-vit-base-patch32-vision-onnx",
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

  private var activeTasks: [String: Task<Void, Never>] = [:]
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

    let task = Task {
      await performDownload(model)
    }
    activeTasks[model.id] = task
  }

  func cancel(_ model: CLIPModelSpec) {
    activeTasks[model.id]?.cancel()
    activeTasks[model.id] = nil
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

  private func performDownload(_ model: CLIPModelSpec) async {
    let modelDir = Self.modelsDirectoryURL.appendingPathComponent(model.id)

    do {
      try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
    } catch {
      modelStates[model.id] = .error("Failed to create directory: \(error.localizedDescription)")
      return
    }

    let totalBytes = model.totalSizeBytes
    var downloadedBytes: Int64 = 0

    modelStates[model.id] = .downloading(progress: 0)

    for file in model.files {
      if Task.isCancelled { return }

      let destinationURL = modelDir.appendingPathComponent(file.filename)

      // Skip already-downloaded files (enables resume after partial failure)
      if fileManager.fileExists(atPath: destinationURL.path) {
        downloadedBytes += file.sizeBytes
        modelStates[model.id] = .downloading(
          progress: Double(downloadedBytes) / Double(totalBytes)
        )
        continue
      }

      do {
        let (tempURL, response) = try await URLSession.shared.download(from: model.downloadURL(for: file))

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
          let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
          throw URLError(.badServerResponse, userInfo: [
            NSLocalizedDescriptionKey: "Server returned status \(statusCode)"
          ])
        }

        // Atomic move from system temp to final location
        if fileManager.fileExists(atPath: destinationURL.path) {
          try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)

        downloadedBytes += file.sizeBytes
        modelStates[model.id] = .downloading(
          progress: Double(downloadedBytes) / Double(totalBytes)
        )
      } catch is CancellationError {
        return
      } catch {
        modelStates[model.id] = .error(error.localizedDescription)
        activeTasks[model.id] = nil
        return
      }
    }

    modelStates[model.id] = .downloaded
    activeTasks[model.id] = nil
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
