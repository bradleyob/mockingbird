import Foundation
import Testing
@testable import MockingBirdCore

@Suite("ProfileLibrary decoding and filtering")
struct ProfileLibraryDecodingTests {
    private func profileJSON(weights: String, root: String = "\"C\"") -> String {
        #"{"name":"C test","root":\#(root),"category":"custom","scaleName":"test","weights":\#(weights)}"#
    }

    @Test("decodes a valid library with string roots")
    func decodesValid() throws {
        let json = #"{"profiles":[\#(profileJSON(weights: "[1,0,0,0,1,0,0,1,0,0,0,0]", root: "\"G\""))]}"#
        let library = try JSONDecoder().decode(ProfileLibrary.self, from: Data(json.utf8))
        #expect(library.profiles.count == 1)
        #expect(library.profiles.first?.root == .g)
    }

    @Test("rejects a profile without exactly 12 weights", arguments: ["[1,2,3]", "[1,1,1,1,1,1,1,1,1,1,1,1,1]", "[]"])
    func rejectsBadWeightCount(weights: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScaleProfile.self, from: Data(profileJSON(weights: weights).utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfileLibrary.self,
                                     from: Data(#"{"profiles":[\#(profileJSON(weights: weights))]}"#.utf8))
        }
    }

    @Test("rejects an empty library")
    func rejectsEmpty() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfileLibrary.self, from: Data(#"{"profiles":[]}"#.utf8))
        }
    }

    @Test("rejects an unknown root")
    func rejectsUnknownRoot() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScaleProfile.self,
                                     from: Data(profileJSON(weights: "[1,0,0,0,0,0,0,0,0,0,0,0]", root: "\"H\"").utf8))
        }
    }

    @Test("profiles(for: ScaleCategory) returns only that category", arguments: ScaleCategory.allCases)
    func filterByCategory(category: ScaleCategory) {
        let library = ProfileLibrary.default
        let filtered = library.profiles(for: category)
        #expect(filtered.allSatisfy { $0.category == category })
        #expect(filtered.count == library.profiles.filter { $0.category == category }.count)
    }

    @Test("profiles(for: PitchClass) returns one profile per scale type", arguments: PitchClass.allCases)
    func filterByRoot(root: PitchClass) {
        let library = ProfileLibrary.default
        let filtered = library.profiles(for: root)
        #expect(filtered.allSatisfy { $0.root == root })
        #expect(filtered.count == library.profiles.count / 12)
    }
}
