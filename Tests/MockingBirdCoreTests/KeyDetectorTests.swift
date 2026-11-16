import Testing
@testable import MockingBirdCore

@Suite("KeyDetector")
struct KeyDetectorTests {

    private let flat = ChromaVector(
        bins: [Float](repeating: Float(1.0 / 12.0.squareRoot()), count: 12),
        sampleRate: 44100,
        windowSize: 4096
    )

    @Test("confidence is within [0, 1]")
    func confidenceIsNormalized() {
        let result = KeyDetector(library: .default, numAlternates: 3).detect(flat)
        #expect(result.confidence >= 0 && result.confidence <= 1)
    }

    @Test("alternate count respects numAlternates")
    func alternateCountRespected() {
        let result = KeyDetector(library: .default, numAlternates: 3).detect(flat)
        #expect(result.alternates.count <= 3)
    }

    @Test("C-E-G emphasised chroma returns the C major family")
    func cMajorChroma() {
        var bins = [Float](repeating: 0.1, count: 12)
        bins[0] = 1.0
        bins[4] = 0.9
        bins[7] = 0.8
        let l2 = bins.map { $0 * $0 }.reduce(0, +).squareRoot()
        let chroma = ChromaVector(bins: bins.map { $0 / l2 }, sampleRate: 44100, windowSize: 4096)
        let result = KeyDetector(library: .default, numAlternates: 3).detect(chroma)

        let acceptable: Set<String> = ["C major", "A minor", "C major pentatonic"]
        #expect(acceptable.contains("\(result.key) \(result.scaleName)"),
                "got \(result.key) \(result.scaleName)")
    }
}
