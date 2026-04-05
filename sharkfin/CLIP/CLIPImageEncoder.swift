import Foundation
import OnnxRuntimeBindings

/// Wraps the ONNX Runtime vision session for CLIP image encoding.
final class CLIPImageEncoder: @unchecked Sendable {
  
  nonisolated(unsafe) private let session: ORTSession
  private nonisolated let outputName: String
  
  nonisolated init(modelPath: URL) throws {
    let env = try ORTEnv(loggingLevel: .warning)
    
    let options = try ORTSessionOptions()
    // Use CoreML execution provider for GPU acceleration
    try? options.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions())
    
    self.session = try ORTSession(
      env: env,
      modelPath: modelPath.path,
      sessionOptions: options
    )
    
    // Discover actual output tensor name
    let outputNames = try session.outputNames()
    self.outputName = outputNames.first ?? "image_embeds"
  }
  
  /// Encode a preprocessed image tensor [1,3,224,224] → normalized [512] embedding.
  nonisolated func encode(pixelValues: Data) throws -> [Float] {
    let inputTensor = try ORTValue(
      tensorData: NSMutableData(data: pixelValues),
      elementType: .float,
      shape: [1, 3, 224, 224] as [NSNumber]
    )
    
    // Discover actual input name
    let inputNames = try session.inputNames()
    let inputName = inputNames.first ?? "pixel_values"
    
    let outputs = try session.run(
      withInputs: [inputName: inputTensor],
      outputNames: Set([outputName]),
      runOptions: nil
    )
    
    guard let output = outputs[outputName] else {
      throw CLIPError.missingOutput(outputName)
    }
    
    let outputData = try output.tensorData() as Data
    var embedding = outputData.withUnsafeBytes { buffer in
      Array(buffer.bindMemory(to: Float.self))
    }
    
    // Take only 512 dims if output is larger
    if embedding.count > 512 {
      embedding = Array(embedding.prefix(512))
    }
    
    return Self.l2Normalize(embedding)
  }
  
  /// L2-normalize a vector to unit length.
  nonisolated static func l2Normalize(_ v: [Float]) -> [Float] {
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    guard norm > 1e-12 else { return v }
    return v.map { $0 / norm }
  }
}
