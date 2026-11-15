import Foundation
import Testing
import MockingBirdTestSupport
@testable import MockingBirdCore

@Suite("AnalysisPipeline")
struct AnalysisPipelineTests {

    private func results(
        _ samples: [Float],
        config: AudioConfig = AudioConfig(),
        aggregation: ChromaAggregation = .cumulative,
        chunkSize: Int = 4096
    ) async throws -> [KeyResult] {
        let pipeline = try AnalysisPipeline(source: SyntheticSource(samples: samples, chunkSize: chunkSize),
                                            config: config, aggregation: aggregation)
        var collected: [KeyResult] = []
        for try await result in try await pipeline.start() {
            collected.append(result)
        }
        return collected
    }

    @Test("all confidences are within [0, 1]")
    func confidenceInRange() async throws {
        let all = try await results(ToneSynth.chord(ToneSynth.triad(root: 60, minor: false)))
        #expect(!all.isEmpty)
        for result in all {
            #expect(result.confidence >= 0 && result.confidence <= 1)
            for alternate in result.alternates {
                #expect(alternate.confidence >= 0 && alternate.confidence <= 1)
            }
        }
    }

    @Test("alternate count respects config")
    func alternateCountRespected() async throws {
        let config = AudioConfig(numAlternates: 2)
        let all = try await results(ToneSynth.chord(ToneSynth.triad(root: 60, minor: false)), config: config)
        for result in all {
            #expect(result.alternates.count <= 2)
        }
    }

    @Test("result count is floor((N - windowSize) / hopSize) + 1", arguments: [
        (4096, 4096, 2048), (4097, 4096, 2048), (6143, 4096, 2048), (6144, 4096, 2048),
        (44100, 4096, 2048), (44100, 4096, 1000), (44100, 8192, 8192), (30000, 1024, 1),
    ])
    func resultCount(sampleCount: Int, windowSize: Int, hopSize: Int) async throws {
        let config = AudioConfig(windowSize: windowSize, hopSize: hopSize)
        let all = try await results(ToneSynth.chord([60], duration: Double(sampleCount) / 44100 + 1)
                                        .prefix(sampleCount).map { $0 }, config: config)
        #expect(all.count == (sampleCount - windowSize) / hopSize + 1)
    }

    @Test("timestamps are (windowIndex * hopSize + windowSize) / sampleRate", arguments: [
        AudioConfig(), AudioConfig(sampleRate: 48000, windowSize: 8192, hopSize: 1024),
    ])
    func timestamps(config: AudioConfig) async throws {
        let all = try await results(ToneSynth.majorCadence(root: 60, sampleRate: config.sampleRate), config: config)
        #expect(!all.isEmpty)
        for (index, result) in all.enumerated() {
            #expect(result.timestamp == Double(index * config.hopSize + config.windowSize) / config.sampleRate)
        }
    }

    @Test("chunk size does not change results", arguments: [1, 1000, 10000])
    func chunkSizeInvariant(chunkSize: Int) async throws {
        let samples = Array(ToneSynth.majorCadence(root: 57).prefix(44100))
        let reference = try await results(samples, chunkSize: 4096)
        let chunked = try await results(samples, chunkSize: chunkSize)
        #expect(chunked == reference)
    }

    @Test("a stream shorter than one window yields nothing and finishes", arguments: [0, 1, 4095])
    func shortStream(sampleCount: Int) async throws {
        let all = try await results([Float](repeating: 0.5, count: sampleCount))
        #expect(all.isEmpty)
    }

    @Test("rolling follows a key change; cumulative still reflects both halves")
    func rollingFollowsKeyChange() async throws {
        let samples = ToneSynth.majorCadence(root: 60) + ToneSynth.majorCadence(root: 66)
        // 20 windows (~0.93 s) hold only the final F# tonic triad, which a major and a
        // major pentatonic profile explain equally well: require the root, and F# major
        // as winner or alternate.
        let rolling = try #require(try await results(samples, aggregation: .rolling(windows: 20)).last)
        #expect(rolling.key == .fSharp, "\(rolling)")
        let candidates = [(rolling.key, rolling.scaleName)] + rolling.alternates.map { ($0.key, $0.scaleName) }
        #expect(candidates.contains { $0.0 == .fSharp && $0.1 == "major" }, "\(rolling)")

        // 84 windows start at sample 87 * 2048 = 178176, past the 176400-sample C major half,
        // so they hold exactly the F# major cadence: exactly F# major.
        let wider = try #require(try await results(samples, aggregation: .rolling(windows: 84)).last)
        #expect(wider.key == .fSharp && wider.scaleName == "major", "\(wider)")

        let cumulative = try #require(try await results(samples, aggregation: .cumulative).last)
        #expect(cumulative != rolling)

        // The cumulative result is the detection over the summed chroma of every window.
        let config = AudioConfig()
        let fft = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)
        let windowCount = (samples.count - config.windowSize) / config.hopSize + 1
        let total = (0..<windowCount).reduce([Float](repeating: 0, count: 12)) { sum, index in
            let start = index * config.hopSize
            let energy = extractor.extractEnergy(fft.process(Array(samples[start..<(start + config.windowSize)])))
            return zip(sum, energy).map { $0 + $1 }
        }
        let expected = KeyDetector(library: .default, numAlternates: 3)
            .detect(extractor.normalized(total), timestamp: cumulative.timestamp)
        #expect(cumulative.key == expected.key && cumulative.scaleName == expected.scaleName)
        #expect(abs(cumulative.confidence - expected.confidence) < 1e-3)
    }

    @Test("perWindow matches detect(extract(process(window))) for every window")
    func perWindowMatchesDirect() async throws {
        let config = AudioConfig()
        let samples = Array(ToneSynth.scaleMelody(root: 62, minor: true).prefix(44100 * 2))
        let all = try await results(samples, aggregation: .perWindow)
        let fft = try FFTProcessor(config: config)
        let extractor = ChromaExtractor(config: config)
        let detector = KeyDetector(library: .default, numAlternates: config.numAlternates)
        #expect(all.count == (samples.count - config.windowSize) / config.hopSize + 1)
        for (index, result) in all.enumerated() {
            let start = index * config.hopSize
            let window = Array(samples[start..<(start + config.windowSize)])
            let direct = detector.detect(extractor.extract(fft.process(window)), timestamp: result.timestamp)
            #expect(result == direct, "window \(index)")
        }
    }

    @Test("a consumer that stops iterating cancels the reader and releases the source")
    func consumerCancellation() async throws {
        let source = EndlessSource()
        let pipeline = try AnalysisPipeline(source: source)
        var received = 0
        for try await _ in try await pipeline.start() {
            received += 1
            if received == 3 { break }
        }
        #expect(received == 3)
        try await waitUntil { source.terminationCount == 1 }
    }

    @Test("stop() ends the result stream of a live source")
    func stopEndsStream() async throws {
        let source = EndlessSource()
        let pipeline = try AnalysisPipeline(source: source)
        let stream = try await pipeline.start()
        let consumer = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count == 2 { await pipeline.stop() }
            }
            return count
        }
        let count = try await consumer.value
        #expect(count >= 2)
        #expect(source.stopCount >= 1)
        try await waitUntil { source.terminationCount == 1 }
    }

    private func waitUntil(timeout: Double = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("condition not met within \(timeout) s")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
