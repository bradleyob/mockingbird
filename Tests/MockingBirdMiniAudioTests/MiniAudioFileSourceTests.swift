import Foundation
import MockingBirdCore
import MockingBirdTestSupport
import Testing
@testable import AudioSourceMiniAudio

@Suite(.timeLimit(.minutes(1))) struct MiniAudioFileSourceTests {
    private static let cadence = ToneSynth.majorCadence(root: 60)

    private func withFile<T>(_ data: Data, extension ext: String, _ body: (URL) async throws -> T) async throws -> T {
        let url = try AudioFixture.writeTemporary(data, fileExtension: ext)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }

    private func totalSamples(_ source: MiniAudioFileSource, sampleRate: Double) async throws -> [Float] {
        var samples: [Float] = []
        for try await chunk in try source.start(sampleRate: sampleRate) {
            samples += chunk
        }
        return samples
    }

    @Test func wavCadenceDeliversEveryFrame() async throws {
        let samples = try await withFile(AudioFixture.wav16(Self.cadence), extension: "wav") { url in
            try await totalSamples(MiniAudioFileSource(url: url), sampleRate: 44100)
        }
        #expect(abs(samples.count - 176_400) <= 1764)
    }

    @Test func resamplesTo48k() async throws {
        let samples = try await withFile(AudioFixture.wav16(Self.cadence), extension: "wav") { url in
            try await totalSamples(MiniAudioFileSource(url: url), sampleRate: 48000)
        }
        #expect(abs(samples.count - 192_000) <= 1920)
    }

    @Test func decodedCadenceAnalysesAsC() async throws {
        let last = try await withFile(AudioFixture.wav16(Self.cadence), extension: "wav") { url in
            let pipeline = try AnalysisPipeline(source: MiniAudioFileSource(url: url), aggregation: .cumulative)
            var last: KeyResult?
            for try await result in try await pipeline.start() {
                last = result
            }
            return last
        }
        #expect(try #require(last).key == .c)
    }

    @Test func missingFileIsATypedError() {
        let source = MiniAudioFileSource(url: URL(fileURLWithPath: "/nonexistent/cadence.wav"))
        #expect(throws: AudioSourceError.self) { try source.start(sampleRate: 44100) }
    }

    @Test func garbageFileIsFormatUnsupported() async throws {
        try await withFile(Data(repeating: 0x41, count: 5000), extension: "wav") { url in
            #expect {
                try MiniAudioFileSource(url: url).start(sampleRate: 44100)
            } throws: { error in
                guard case .formatUnsupported = error as? AudioSourceError else { return false }
                return true
            }
        }
    }

    @Test func stopEndsTheStreamEarly() async throws {
        let long = AudioFixture.wav16([Float](repeating: 0.1, count: 44100 * 60))
        let count = try await withFile(long, extension: "wav") { url in
            let source = MiniAudioFileSource(url: url)
            var count = 0
            for try await chunk in try source.start(sampleRate: 44100) {
                count += chunk.count
                if count > 44100 {
                    source.stop()
                }
            }
            return count
        }
        #expect(count < 44100 * 60)
    }
}
