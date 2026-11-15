import Foundation
import MockingBirdTestSupport
import Testing

// Phase 0 placeholder so the test target compiles. Track B replaces this file.
@Test func placeholderCLITargetBuildsAndBinaryIsLocatable() throws {
    let binary = try BuiltProducts.executable("mockingbird")
    #expect(FileManager.default.isExecutableFile(atPath: binary.path))
}
