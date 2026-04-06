import Foundation
import OnnxRuntimeBindings
import Tokenizers

/// Abstraction for text-to-embedding encoding, enabling test doubles.
nonisolated protocol TextEncoding: Sendable {
  func encode(text: String) throws -> [Float]
}

/// Wraps the ONNX Runtime text session + BPE tokenizer for CLIP text encoding.
final class CLIPTextEncoder: @unchecked Sendable, TextEncoding {

  nonisolated(unsafe) private let session: ORTSession
  private nonisolated let tokenizer: any Tokenizer
  private nonisolated let outputName: String
  private nonisolated let maxLength = 77

  nonisolated init(modelPath: URL, tokenizerFolder: URL) async throws {
    let env = try ORTEnv(loggingLevel: .warning)

    // CPU-only for text model (small, fast, avoids CoreML dynamic shape issues)
    self.session = try ORTSession(
      env: env,
      modelPath: modelPath.path,
      sessionOptions: nil
    )

    // Patch tokenizer_config.json if needed — CLIP uses standard BPE but
    // declares "CLIPTokenizer" which swift-transformers doesn't recognize.
    Self.patchTokenizerConfigIfNeeded(in: tokenizerFolder)

    // Load BPE tokenizer from local folder
    self.tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolder)

    let outputNames = try session.outputNames()
    self.outputName = outputNames.first ?? "text_embeds"
  }

  /// Replace unsupported "CLIPTokenizer" class with the standard BPE tokenizer class.
  private nonisolated static func patchTokenizerConfigIfNeeded(in folder: URL) {
    let configURL = folder.appendingPathComponent("tokenizer_config.json")
    guard let data = try? Data(contentsOf: configURL),
      var json = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      let tokenizerClass = json["tokenizer_class"] as? String,
      tokenizerClass == "CLIPTokenizer"
    else { return }

    json["tokenizer_class"] = "PreTrainedTokenizerFast"
    if let patched = try? JSONSerialization.data(
      withJSONObject: json,
      options: .prettyPrinted
    ) {
      try? patched.write(to: configURL)
    }
  }

  /// Encode text query → normalized [512] embedding.
  nonisolated func encode(text: String) throws -> [Float] {
    // Tokenize
    let encoded = tokenizer(text)

    // Pad/truncate to 77 tokens — CLIP ONNX models expect Int64
    var inputIds = encoded.map { Int64($0) }
    var attentionMask: [Int64] = Array(repeating: 1, count: inputIds.count)

    inputIds.removeLast(max(0, inputIds.count - maxLength))
    attentionMask.removeLast(max(0, attentionMask.count - maxLength))

    while inputIds.count < maxLength {
      inputIds.append(0)
      attentionMask.append(0)
    }

    // Create tensors with Int64 element type (matching ONNX model expectations)
    let idsData = inputIds.withUnsafeBufferPointer { Data(buffer: $0) }
    let maskData = attentionMask.withUnsafeBufferPointer { Data(buffer: $0) }

    let idsTensor = try ORTValue(
      tensorData: NSMutableData(data: idsData),
      elementType: .int64,
      shape: [1, NSNumber(value: maxLength)]
    )
    let maskTensor = try ORTValue(
      tensorData: NSMutableData(data: maskData),
      elementType: .int64,
      shape: [1, NSNumber(value: maxLength)]
    )

    // Discover input names
    let inputNames = try session.inputNames()
    var inputs: [String: ORTValue] = [:]
    for name in inputNames {
      if name.contains("input_id") || name == "input_ids" {
        inputs[name] = idsTensor
      } else if name.contains("attention") || name == "attention_mask" {
        inputs[name] = maskTensor
      }
    }

    // Fallback if name discovery didn't match
    if inputs.isEmpty {
      inputs = ["input_ids": idsTensor, "attention_mask": maskTensor]
    }

    let outputs = try session.run(
      withInputs: inputs,
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

    if embedding.count > 512 {
      embedding = Array(embedding.prefix(512))
    }

    return CLIPImageEncoder.l2Normalize(embedding)
  }
}
