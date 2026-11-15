import Testing
@testable import MockingBirdCore

@Suite("ScaleCategory")
struct ScaleCategoryTests {
    @Test("has the documented cases and raw values")
    func cases() {
        #expect(ScaleCategory.allCases.map(\.rawValue)
                == ["major", "minor", "mode", "blues", "jazz", "pentatonic", "symmetric", "custom"])
    }
}
