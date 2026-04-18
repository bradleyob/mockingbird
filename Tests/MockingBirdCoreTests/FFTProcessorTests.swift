import XCTest
@testable import MockingBirdCore

final class FFTProcessorTests: XCTestCase {

    func testSineWaveProducesExpectedPeakBin() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)

        // 440 Hz sine (A4) — expected peak near bin 440*4096/44100 ≈ bin 40
        let samples = sineWave(frequency: 440, sampleRate: 44100, count: 4096)
        let magnitudes = processor.process(samples)

        XCTAssertEqual(magnitudes.count, config.fftSize / 2)

        let peakBin = magnitudes.indices.max(by: { magnitudes[$0] < magnitudes[$1] })!
        let expectedBin = Int((440.0 * Double(config.fftSize) / 44100).rounded())
        // Allow ±2 bins for windowing leakage
        XCTAssertLessThanOrEqual(abs(peakBin - expectedBin), 2,
            "Peak bin \(peakBin) not near expected \(expectedBin)")
    }

    func testOutputLengthMatchesFftSize() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let samples = [Float](repeating: 0.1, count: 4096)
        let magnitudes = processor.process(samples)
        XCTAssertEqual(magnitudes.count, config.fftSize / 2)
    }

    func testZeroPadDoublesOutputLength() throws {
        let config = AudioConfig(windowSize: 1024, hopSize: 512, zeroPad: true)
        let processor = try FFTProcessor(config: config)
        let samples = [Float](repeating: 0, count: 1024)
        let magnitudes = processor.process(samples)
        XCTAssertEqual(magnitudes.count, 1024) // fftSize=2048, half=1024
    }

    // MARK: - Helpers

    private func sineWave(frequency: Double, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { n in
            Float(sin(2 * Double.pi * frequency * Double(n) / sampleRate))
        }
    }
}
