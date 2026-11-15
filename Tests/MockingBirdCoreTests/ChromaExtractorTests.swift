// Phase 0: XCTest is unavailable with Command Line Tools only. Track A (MB-18) migrates
// this file to Swift Testing and removes this guard.
#if canImport(XCTest)
import XCTest
@testable import MockingBirdCore

final class ChromaExtractorTests: XCTestCase {

    func testOutputIsL2Normalized() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)

        let samples = sineWave(frequency: 440, sampleRate: 44100, count: 4096)
        let magnitudes = processor.process(samples)
        let chroma = extractor.extract(magnitudes)

        let norm = chroma.bins.map { $0 * $0 }.reduce(0, +).squareRoot()
        XCTAssertEqual(Double(norm), 1.0, accuracy: 0.001)
    }

    func testBinCountIsAlways12() throws {
        let config = AudioConfig()
        let processor = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)
        let magnitudes = processor.process([Float](repeating: 0.1, count: config.windowSize))
        let chroma = extractor.extract(magnitudes)
        XCTAssertEqual(chroma.bins.count, 12)
    }

    func testA440SineEmphasizesPitchClassA() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)

        let samples = sineWave(frequency: 440, sampleRate: 44100, count: 4096)
        let magnitudes = processor.process(samples)
        let chroma = extractor.extract(magnitudes)

        // A = pitch class index 9
        let peakBin = chroma.bins.indices.max(by: { chroma.bins[$0] < chroma.bins[$1] })!
        XCTAssertEqual(peakBin, PitchClass.a.rawValue,
            "Expected A (9) to dominate, got bin \(peakBin): \(chroma.bins)")
    }

    // MARK: - Helpers

    private func sineWave(frequency: Double, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { n in
            Float(sin(2 * Double.pi * frequency * Double(n) / sampleRate))
        }
    }
}
#endif
