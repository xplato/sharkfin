import Foundation

enum CLIPError: LocalizedError {
  case missingOutput(String)
  case invalidEmbedding
  case modelNotReady
  
  var errorDescription: String? {
    switch self {
    case .missingOutput(let name):
      "Missing expected output tensor: \(name)"
    case .invalidEmbedding:
      "Embedding has unexpected dimensions"
    case .modelNotReady:
      "CLIP models are not downloaded yet"
    }
  }
}
