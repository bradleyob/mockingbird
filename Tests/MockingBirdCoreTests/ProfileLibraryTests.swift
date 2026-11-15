import Testing
@testable import MockingBirdCore

@Suite("ProfileLibrary")
struct ProfileLibraryTests {

    @Test("default library is non-empty")
    func nonEmpty() {
        #expect(!ProfileLibrary.default.profiles.isEmpty)
    }

    @Test("every profile has 12 weights")
    func twelveWeights() {
        for profile in ProfileLibrary.default.profiles {
            #expect(profile.weights.count == 12, "\(profile.name)")
        }
    }

    @Test("every profile is unit-normalised")
    func unitNorm() {
        for profile in ProfileLibrary.default.profiles {
            let norm = profile.weights.map { $0 * $0 }.reduce(0, +).squareRoot()
            #expect(abs(norm - 1) < 0.01, "\(profile.name)")
        }
    }

    @Test("transposition rotates weights right")
    func transpositionRotates() throws {
        let cMajor = try #require(ProfileLibrary.default.profiles.first { $0.scaleName == "major" && $0.root == .c })
        let dMajor = cMajor.transposed(by: 2)
        #expect(dMajor.root == .d)
        #expect(dMajor.scaleName == "major")
        #expect(abs(dMajor.weights[2] - cMajor.weights[0]) < 0.001)
        #expect(abs(dMajor.weights[4] - cMajor.weights[2]) < 0.001)
        #expect(abs(dMajor.weights[0] - cMajor.weights[10]) < 0.001)
    }

    @Test("every scale type has 12 transpositions, one per root")
    func twelveTranspositions() {
        let library = ProfileLibrary.default
        for name in Set(library.profiles.map(\.scaleName)) {
            let roots = library.profiles.filter { $0.scaleName == name }.map(\.root)
            #expect(roots.count == 12, "\(name)")
            #expect(Set(roots).count == 12, "\(name)")
        }
    }
}
