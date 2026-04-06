import Testing

@testable import Sharkfin

struct SearchFilterTests {

  @Test func emptyFiltersByDefault() {
    let filters = SearchFilters()
    #expect(filters.isEmpty)
    #expect(filters.fileTypes.isEmpty)
  }

  @Test func isNotEmptyWithFileTypes() {
    let filters = SearchFilters(fileTypes: ["jpg", "png"])
    #expect(!filters.isEmpty)
  }

  @Test func equatableConformance() {
    let a = SearchFilters(fileTypes: ["jpg"])
    let b = SearchFilters(fileTypes: ["jpg"])
    let c = SearchFilters(fileTypes: ["png"])
    #expect(a == b)
    #expect(a != c)
  }
}
