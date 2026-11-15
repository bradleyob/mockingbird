import Testing
@testable import MockingBirdCore

@Suite("ChromaExtractor")
struct ChromaExtractorTests {

    @Test("output is L2-normalised")
    func outputIsL2Normalized() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)
        let chroma = extractor.extract(processor.process(Signal.sine(frequency: 440, count: 4096)))

        let norm = chroma.bins.map { $0 * $0 }.reduce(0, +).squareRoot()
        #expect(abs(norm - 1) < 0.001)
    }

    @Test("bin count is always 12")
    func binCountIsAlways12() throws {
        let config = AudioConfig()
        let processor = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)
        let chroma = extractor.extract(processor.process([Float](repeating: 0.1, count: config.windowSize)))
        #expect(chroma.bins.count == 12)
    }

    @Test("a 440 Hz sine emphasises pitch class A")
    func a440EmphasizesA() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)
        let chroma = extractor.extract(processor.process(Signal.sine(frequency: 440, count: 4096)))

        #expect(Signal.argmax(chroma.bins) == PitchClass.a.rawValue, "\(chroma.bins)")
    }
}
