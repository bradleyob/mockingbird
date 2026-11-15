import Foundation
import Testing
import MockingBirdTestSupport
@testable import MockingBirdCore

@Suite("Key detection accuracy")
struct KeyDetectionAccuracyTests {

    @Test("default config detects the exact key", arguments: AccuracyCase.all)
    func matrix(testCase: AccuracyCase) async throws {
        let result = try #require(try await testCase.detect())
        #expect(testCase.isCorrect(result),
                "expected \(testCase.expectedKey) \(testCase.expectedScale), got \(result.key) \(result.scaleName)")
        #expect(result.confidence >= 0.75, "confidence \(result.confidence)")
    }

    @Test("major/minor-only library detects the exact key", arguments: AccuracyCase.all)
    func matrixMajorMinorOnly(testCase: AccuracyCase) async throws {
        let library = ProfileLibrary(profiles: ProfileLibrary.default.profiles(for: .major)
                                     + ProfileLibrary.default.profiles(for: .minor))
        let result = try await testCase.detect(library: library)
        #expect(testCase.isCorrect(result), "got \(String(describing: result))")
    }

    @Test("matrix holds under other configurations (at least 57/60)", arguments: [
        AudioConfig(sampleRate: 48000),
        AudioConfig(windowSize: 8192, hopSize: 4096),
        AudioConfig(zeroPad: true),
    ])
    func matrixVariants(config: AudioConfig) async throws {
        var misses: [String] = []
        for testCase in AccuracyCase.all {
            let result = try await testCase.detect(config: config)
            if !testCase.isCorrect(result) {
                misses.append("\(testCase.testDescription) -> \(result.map { "\($0.key) \($0.scaleName)" } ?? "none")")
            }
        }
        let correct = AccuracyCase.all.count - misses.count
        #expect(correct >= 57, "\(correct)/60 at \(config); misses: \(misses)")
    }

    @Test("a single tone's chroma peaks at its pitch class", arguments: [40, 45, 52, 57, 60, 69, 81])
    func singleTonePitchClass(midi: Int) throws {
        let config = AudioConfig()
        let samples = Array(ToneSynth.chord([midi], harmonics: 4).dropFirst(8192).prefix(config.windowSize))
        let chroma = ChromaExtractor(config: config).extract(try FFTProcessor(config: config).process(samples))
        #expect(Signal.argmax(chroma.bins) == midi % 12, "midi \(midi): \(chroma.bins)")
    }

    @Test("a lone major triad names its root, with <root> major among the top four",
          arguments: [48, 55, 60, 62, 67])
    func loneTriad(root: Int) async throws {
        let pipeline = try AnalysisPipeline(
            source: SyntheticSource(samples: ToneSynth.chord(ToneSynth.triad(root: root, minor: false))))
        var last: KeyResult?
        for try await result in try await pipeline.start() { last = result }
        let result = try #require(last)
        let key = PitchClass.allCases[root % 12]
        #expect(result.key == key, "got \(result)")
        let top = [(result.key, result.scaleName)] + result.alternates.map { ($0.key, $0.scaleName) }
        #expect(top.contains { $0.0 == key && $0.1 == "major" }, "\(top)")
    }

    @Test("white noise has low confidence")
    func whiteNoise() async throws {
        var generator = SplitMix64(seed: 0x5EED)
        let noise = (0..<(44100 * 4)).map { _ in Float.random(in: -1...1, using: &generator) }
        let pipeline = try AnalysisPipeline(source: SyntheticSource(samples: noise))
        var last: KeyResult?
        for try await result in try await pipeline.start() { last = result }
        let result = try #require(last)
        #expect(result.confidence < 0.6, "noise confidence \(result.confidence)")
    }

    @Test("silence gives confidence 0 and no NaN")
    func silence() async throws {
        let pipeline = try AnalysisPipeline(source: SyntheticSource(samples: [Float](repeating: 0, count: 44100)))
        var results: [KeyResult] = []
        for try await result in try await pipeline.start() { results.append(result) }
        #expect(!results.isEmpty)
        for result in results {
            #expect(result.confidence == 0)
            #expect(!result.confidence.isNaN)
            #expect(result.alternates.allSatisfy { $0.confidence == 0 && !$0.confidence.isNaN })
        }
    }

    @Test("confidences are in [0, 1], alternates sorted descending and bounded", arguments: [0, 1, 3, 5])
    func resultShape(numAlternates: Int) async throws {
        let config = AudioConfig(numAlternates: numAlternates)
        let pipeline = try AnalysisPipeline(
            source: SyntheticSource(samples: ToneSynth.majorCadence(root: 50)), config: config)
        for try await result in try await pipeline.start() {
            #expect(result.confidence >= 0 && result.confidence <= 1)
            #expect(result.alternates.count == numAlternates)
            let confidences = [result.confidence] + result.alternates.map(\.confidence)
            #expect(confidences.allSatisfy { $0 >= 0 && $0 <= 1 && !$0.isNaN })
            #expect(zip(confidences, confidences.dropFirst()).allSatisfy { $0 >= $1 })
        }
    }
}
