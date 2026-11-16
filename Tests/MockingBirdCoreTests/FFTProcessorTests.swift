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

    @Test("with zero padding, the same window twice gives identical output")
    func zeroPadIsStateless() throws {
        let config = AudioConfig(zeroPad: true)
        let processor = try FFTProcessor(config: config)
        let window = Signal.sine(frequency: 440, count: config.windowSize)
        let first = processor.process(window)
        let second = processor.process(window)
        #expect(first == second)
    }

    @Test("with zero padding, earlier windows do not leak into later ones")
    func zeroPadDoesNotLeak() throws {
        let config = AudioConfig(zeroPad: true)
        let fresh = try FFTProcessor(config: config)
        let used = try FFTProcessor(config: config)
        _ = used.process(Signal.sine(frequency: 1000, count: config.windowSize))
        let window = Signal.sine(frequency: 440, count: config.windowSize)
        #expect(used.process(window) == fresh.process(window))
    }

    @Test("with zero padding, a 440 Hz sine peaks at the expected bin of the doubled FFT")
    func zeroPadPeak() throws {
        let config = AudioConfig(zeroPad: true)
        let magnitudes = try FFTProcessor(config: config).process(Signal.sine(frequency: 440, count: config.windowSize))
        #expect(magnitudes.count == 4096)
        let peak = try #require(Signal.argmax(magnitudes))
        #expect(peak == Int((440.0 * 8192 / 44100).rounded()))
    }

    @Test("zero-padded output matches the portable FFT of the padded window", arguments: [false, true])
    func matchesPortable(zeroPad: Bool) throws {
        let config = AudioConfig(zeroPad: zeroPad)
        let processor = try FFTProcessor(config: config)
        _ = processor.process(Signal.sine(frequency: 777, count: config.windowSize))
        let input = Signal.sine(frequency: 523.25, count: config.windowSize)
        let actual = processor.process(input)
        let windowed = zip(input, FFTProcessor.blackmanWindow(size: config.windowSize)).map { $0 * $1 }
        let expected = RadixTwoFFT(size: config.fftSize).magnitudes(of: windowed)
        let peak = try #require(expected.max())
        for bin in 1..<expected.count {
            #expect(abs(actual[bin] - expected[bin]) <= 1e-3 * max(expected[bin], peak * 1e-4), "bin \(bin)")
        }
    }
}
