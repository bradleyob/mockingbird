import Foundation
import Testing
import MockingBirdTestSupport
@testable import MockingBirdCore

@Suite("FileSource")
struct FileSourceTests {

    @Test("delivers every sample of a raw Float32 file, in bounded chunks")
    func deliversAllSamples() async throws {
        let samples = ToneSynth.majorCadence(root: 60)
        let url = try AudioFixture.writeTemporary(AudioFixture.rawFloat32(samples), fileExtension: "raw")
        defer { try? FileManager.default.removeItem(at: url) }

        var received: [Float] = []
        var largestChunk = 0
        for try await chunk in try FileSource(url: url).start(sampleRate: 44100) {
            received += chunk
            largestChunk = max(largestChunk, chunk.count)
        }
        #expect(received == samples)
        #expect(largestChunk <= 4096)
    }

    @Test("a missing file throws a typed AudioSourceError from start")
    func missingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mockingbird-missing-\(UUID().uuidString).raw")
        #expect(throws: AudioSourceError.self) {
            _ = try FileSource(url: url).start(sampleRate: 44100)
        }
    }

    @Test("stop() ends the stream before the end of the file")
    func stopEndsEarly() async throws {
        let samples = [Float](repeating: 0.5, count: 4096 * 100)
        let url = try AudioFixture.writeTemporary(AudioFixture.rawFloat32(samples), fileExtension: "raw")
        defer { try? FileManager.default.removeItem(at: url) }

        let source = FileSource(url: url)
        var received = 0
        for try await chunk in try source.start(sampleRate: 44100) {
            received += chunk.count
            if received >= 4096 * 2 { source.stop() }
        }
        #expect(received >= 4096 * 2)
        #expect(received < samples.count)
    }

    @Test("feeds the pipeline: a raw C major cadence file is detected as C major")
    func throughPipeline() async throws {
        let url = try AudioFixture.writeTemporary(AudioFixture.rawFloat32(ToneSynth.majorCadence(root: 60)),
                                                  fileExtension: "raw")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try AnalysisPipeline(source: FileSource(url: url))
        var last: KeyResult?
        for try await result in try await pipeline.start() { last = result }
        #expect(last?.key == .c && last?.scaleName == "major")
    }
}
