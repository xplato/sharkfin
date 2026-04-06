import Foundation
import Testing

@testable import Sharkfin

struct L2NormalizeTests {

  @Test func normalizesVectorToUnitLength() {
    let input: [Float] = [3.0, 4.0]
    let result = CLIPImageEncoder.l2Normalize(input)
    #expect(abs(result[0] - 0.6) < 1e-6)
    #expect(abs(result[1] - 0.8) < 1e-6)

    let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
    #expect(abs(norm - 1.0) < 1e-6)
  }

  @Test func handlesZeroVector() {
    let input: [Float] = [0.0, 0.0, 0.0]
    let result = CLIPImageEncoder.l2Normalize(input)
    #expect(result == input)
  }

  @Test func preservesDirectionFor512DimVector() {
    var input = [Float](repeating: 0.1, count: 512)
    input[0] = 1.0
    let result = CLIPImageEncoder.l2Normalize(input)

    // First element should remain proportionally largest
    #expect(result[0] > result[1])

    // Should be unit length
    let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
    #expect(abs(norm - 1.0) < 1e-5)
  }
}
