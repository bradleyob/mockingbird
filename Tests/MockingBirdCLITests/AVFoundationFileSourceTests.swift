#if os(macOS)
import AudioSourceAVFoundation
import Foundation
import MockingBirdCore
import MockingBirdTestSupport
import Testing

@Suite struct AVFoundationFileSourceTests {
    private func totalSamples(_ source: AVFoundationFileSource, sampleRate: Double) async throws -> Int {
        try await source.start(sampleRate: sampleRate).reduce(0) { $0 + $1.count }
    }

    @Test(arguments: [(44100.0, 176_400.0), (48000.0, 192_000.0)])
    func deliversTheWholeFileAtTheRequestedRate(sampleRate: Double, expected: Double) async throws {
        let wav = try DecodedFileTests.cadenceWAV()
        defer { try? FileManager.default.removeItem(at: wav) }
        let count = try await totalSamples(AVFoundationFileSource(url: wav), sampleRate: sampleRate)
        #expect(abs(Double(count) - expected) / expected < 0.01, "got \(count) samples")
    }

    @Test func stereoIsDownmixedToMono() async throws {
        let wav = try DecodedFileTests.cadenceWAV()
        defer { try? FileManager.default.removeItem(at: wav) }
        let stereo = try DecodedFileTests.afconvert(wav, fileExtension: "wav", ["-f", "WAVE", "-d", "LEI16", "-c", "2"])
        defer { try? FileManager.default.removeItem(at: stereo) }
        let count = try await totalSamples(AVFoundationFileSource(url: stereo), sampleRate: 44100)
        #expect(abs(Double(count) - 176_400) / 176_400 < 0.01, "got \(count) samples")
    }

    @Test func samplesMatchTheSourceSignal() async throws {
        let original = ToneSynth.majorCadence(root: 48)
        let wav = try AudioFixture.writeTemporary(AudioFixture.wav16(original), fileExtension: "wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let decoded = try await AVFoundationFileSource(url: wav).start(sampleRate: 44100).reduce([Float]()) { $0 + $1 }
        try #require(decoded.count == original.count)
        let worst = zip(decoded, original).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 1e-3)
    }

    @Test func missingFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mockingbird-missing-\(UUID()).wav")
        #expect(throws: AudioSourceError.self) {
            _ = try AVFoundationFileSource(url: url).start(sampleRate: 44100)
        }
    }

    @Test func undecodableFileThrows() throws {
        let url = try AudioFixture.writeTemporary(Data("not audio".utf8), fileExtension: "wav")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AudioSourceError.self) {
            _ = try AVFoundationFileSource(url: url).start(sampleRate: 44100)
        }
    }

    @Test func stopEndsTheStreamEarly() async throws {
        let long = ToneSynth.chord([60], sampleRate: 44100, duration: 30)
        let wav = try AudioFixture.writeTemporary(AudioFixture.wav16(long), fileExtension: "wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let source = AVFoundationFileSource(url: wav)
        var count = 0
        for try await chunk in try source.start(sampleRate: 44100) {
            count += chunk.count
            source.stop()
        }
        #expect(count < long.count / 2, "delivered \(count) of \(long.count) samples after stop()")
    }
}
#endif
