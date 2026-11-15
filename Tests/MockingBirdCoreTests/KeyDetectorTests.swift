// Phase 0: XCTest is unavailable with Command Line Tools only. Track A (MB-18) migrates
// this file to Swift Testing and removes this guard.
#if canImport(XCTest)
import XCTest
@testable import MockingBirdCore

final class KeyDetectorTests: XCTestCase {

    func testConfidenceIsNormalized() {
        let detector = KeyDetector(library: .default, numAlternates: 3)
        let chroma = ChromaVector(
            bins: [Float](repeating: Float(1.0 / 12.0.squareRoot()), count: 12),
            sampleRate: 44100,
            windowSize: 4096
        )
        let result = detector.detect(chroma)
        XCTAssertGreaterThanOrEqual(result.confidence, 0)
        XCTAssertLessThanOrEqual(result.confidence, 1)
    }

    func testAlternateCountRespected() {
        let detector = KeyDetector(library: .default, numAlternates: 3)
        let chroma = ChromaVector(
            bins: [Float](repeating: Float(1.0 / 12.0.squareRoot()), count: 12),
            sampleRate: 44100,
            windowSize: 4096
        )
        let result = detector.detect(chroma)
        XCTAssertLessThanOrEqual(result.alternates.count, 3)
    }

    func testCMajorChromaReturnsCMajorOrRelative() {
        // C major chroma: emphasize C E G (indices 0, 4, 7)
        var bins = [Float](repeating: 0.1, count: 12)
        bins[0] = 1.0  // C
        bins[4] = 0.9  // E
        bins[7] = 0.8  // G
        let l2 = bins.map { $0 * $0 }.reduce(0, +).squareRoot()
        let normalized = bins.map { $0 / l2 }

        let chroma = ChromaVector(bins: normalized, sampleRate: 44100, windowSize: 4096)
        let detector = KeyDetector(library: .default, numAlternates: 3)
        let result = detector.detect(chroma)

        // Top result should be C major or a closely related key
        let topKeys: Set<String> = ["\(result.key) \(result.scaleName)"]
        let acceptable: Set<String> = ["C major", "A minor", "C major pentatonic"]
        XCTAssertFalse(topKeys.isDisjoint(with: acceptable),
            "Expected C major family, got: \(result.key) \(result.scaleName)")
    }

    func testDefaultLibraryHas12TranspositionsPerScale() {
        let library = ProfileLibrary.default
        // Should have 12 major + 12 minor + more
        let majorProfiles = library.profiles.filter { $0.scaleName == "major" }
        XCTAssertEqual(majorProfiles.count, 12)
        let minorProfiles = library.profiles.filter { $0.scaleName == "minor" }
        XCTAssertEqual(minorProfiles.count, 12)
    }
}
#endif
