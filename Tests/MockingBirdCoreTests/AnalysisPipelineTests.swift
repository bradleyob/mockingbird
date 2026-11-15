import Testing
import MockingBirdTestSupport
@testable import MockingBirdCore

@Suite("AnalysisPipeline")
struct AnalysisPipelineTests {

    private func results(
        _ samples: [Float],
        config: AudioConfig = AudioConfig()
    ) async throws -> [KeyResult] {
        let pipeline = try AnalysisPipeline(source: SyntheticSource(samples: samples), config: config)
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
}
