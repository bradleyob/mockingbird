import Testing
@testable import MockingBirdCore

@Suite("FFTProcessor")
struct FFTProcessorTests {

    @Test("a 440 Hz sine peaks at the expected bin")
    func sinePeaksAtExpectedBin() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let magnitudes = processor.process(Signal.sine(frequency: 440, count: 4096))

        #expect(magnitudes.count == config.fftSize / 2)
        let peak = try #require(Signal.argmax(magnitudes))
        let expected = Int((440.0 * Double(config.fftSize) / 44100).rounded())
        #expect(abs(peak - expected) <= 1)
    }

    @Test("output length is fftSize / 2")
    func outputLengthMatchesFFTSize() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let magnitudes = processor.process([Float](repeating: 0.1, count: 4096))
        #expect(magnitudes.count == config.fftSize / 2)
    }

    @Test("zero padding doubles the output length")
    func zeroPadDoublesOutputLength() throws {
        let config = AudioConfig(windowSize: 1024, hopSize: 512, zeroPad: true)
        let processor = try FFTProcessor(config: config)
        let magnitudes = processor.process([Float](repeating: 0, count: 1024))
        #expect(magnitudes.count == 1024)
    }
}
