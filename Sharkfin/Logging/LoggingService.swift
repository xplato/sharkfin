import Foundation

enum LogLevel: String, Sendable {
  case info = "INFO"
  case debug = "DEBUG"
}

nonisolated final class LoggingService: @unchecked Sendable {
  static let shared = LoggingService()
  
  private let queue = DispatchQueue(
    label: "com.lgx.sharkfin.logging",
    qos: .utility
  )
  private var fileHandle: FileHandle?
  private var buffer = ""
  private var flushWorkItem: DispatchWorkItem?
  
  private let logDirectoryURL: URL
  private let maxLogFiles = 10
  private let flushInterval: TimeInterval = 1.0
  private let bufferFlushThreshold = 4096
  
  init(logDirectory: URL? = nil) {
    self.logDirectoryURL =
    logDirectory
    ?? AppDatabase.dataDirectoryURL.appendingPathComponent(
      "logs",
      isDirectory: true
    )
    queue.sync { setupLogFile() }
    queue.sync { rotateOldLogs() }
  }
  
  deinit {
    queue.sync {
      flush()
      try? fileHandle?.close()
    }
  }
  
  // MARK: - Public API
  
  /// Log at info level (always written).
  func info(_ message: @autoclosure () -> String, category: String? = nil) {
    log(level: .info, category: category, message: message())
  }
  
  /// Log at debug level (only written when debug mode is enabled).
  func debug(_ message: @autoclosure () -> String, category: String? = nil) {
    guard UserDefaults.standard.bool(forKey: StorageKey.debugMode) else {
      return
    }
    log(level: .debug, category: category, message: message())
  }
  
  /// Whether debug mode is currently enabled.
  var isDebugEnabled: Bool {
    UserDefaults.standard.bool(forKey: StorageKey.debugMode)
  }
  
  // MARK: - Internal
  
  private func log(level: LogLevel, category: String?, message: String) {
    let timestamp = Self.timestampFormatter.string(from: Date())
    let categoryPrefix = category.map { "[\($0)] " } ?? ""
    let line = "\(timestamp) [\(level.rawValue)] \(categoryPrefix)\(message)\n"
    
    // Always print to console for Xcode debugging
    print(line, terminator: "")
    
    queue.async { [self] in
      buffer.append(line)
      if buffer.utf8.count >= bufferFlushThreshold {
        flush()
      } else {
        scheduleFlush()
      }
    }
  }
  
  private func flush() {
    guard !buffer.isEmpty, let data = buffer.data(using: .utf8) else { return }
    fileHandle?.write(data)
    buffer = ""
    flushWorkItem?.cancel()
    flushWorkItem = nil
  }
  
  private func scheduleFlush() {
    guard flushWorkItem == nil else { return }
    let item = DispatchWorkItem { [weak self] in
      self?.flush()
      self?.flushWorkItem = nil
    }
    flushWorkItem = item
    queue.asyncAfter(deadline: .now() + flushInterval, execute: item)
  }
  
  private func setupLogFile() {
    let fm = FileManager.default
    try? fm.createDirectory(
      at: logDirectoryURL,
      withIntermediateDirectories: true
    )
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let filename = "sharkfin_\(formatter.string(from: Date())).log"
    let fileURL = logDirectoryURL.appendingPathComponent(filename)
    
    fm.createFile(atPath: fileURL.path, contents: nil)
    fileHandle = try? FileHandle(forWritingTo: fileURL)
    fileHandle?.seekToEndOfFile()
  }
  
  private func rotateOldLogs() {
    let fm = FileManager.default
    guard
      let files = try? fm.contentsOfDirectory(
        at: logDirectoryURL,
        includingPropertiesForKeys: nil
      ).filter({ $0.pathExtension == "log" })
        .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
    else { return }
    
    if files.count > maxLogFiles {
      for file in files.dropFirst(maxLogFiles) {
        try? fm.removeItem(at: file)
      }
    }
  }
  
  private nonisolated static let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
  }()
}
