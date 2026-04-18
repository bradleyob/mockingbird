import XCTest
@testable import MockingBirdCore

final class ProfileLibraryTests: XCTestCase {

    func testDefaultLibraryIsNonEmpty() {
        XCTAssertFalse(ProfileLibrary.default.profiles.isEmpty)
    }

    func testAllProfilesHave12Weights() {
        for profile in ProfileLibrary.default.profiles {
            XCTAssertEqual(profile.weights.count, 12, "\(profile.name) has wrong weight count")
        }
    }

    func testAllProfilesAreApproximatelyNormalized() {
        for profile in ProfileLibrary.default.profiles {
            let norm = profile.weights.map { $0 * $0 }.reduce(0, +).squareRoot()
            XCTAssertEqual(Double(norm), 1.0, accuracy: 0.01, "\(profile.name) is not unit-normalized")
        }
    }

    func testTranspositionPreservesWeightMagnitude() {
        let cMajor = ProfileLibrary.default.profiles.first { $0.scaleName == "major" && $0.root == .c }!
        let dMajor = cMajor.transposed(by: 2)
        XCTAssertEqual(dMajor.root, .d)
        XCTAssertEqual(dMajor.scaleName, "major")
        // Rotation by 2: dMajor[i] == cMajor[(i + 2) % 12]
        XCTAssertEqual(dMajor.weights[0], cMajor.weights[2], accuracy: 0.001)
        XCTAssertEqual(dMajor.weights[2], cMajor.weights[4], accuracy: 0.001)
        XCTAssertEqual(dMajor.weights[10], cMajor.weights[0], accuracy: 0.001)
    }

    func testEachScaleHas12Transpositions() {
        let scaleNames = Set(ProfileLibrary.default.profiles.map(\.scaleName))
        for name in scaleNames {
            let count = ProfileLibrary.default.profiles.filter { $0.scaleName == name }.count
            XCTAssertEqual(count, 12, "Scale '\(name)' has \(count) transpositions, expected 12")
        }
    }
}
