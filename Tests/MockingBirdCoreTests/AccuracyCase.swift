import MockingBirdCore
import Testing
import MockingBirdTestSupport

/// One row of the key-detection accuracy matrix: a ToneSynth signal and the key it is in.
struct AccuracyCase: CustomTestStringConvertible, Sendable {
    enum Material: String, CaseIterable, Sendable {
        case majorCadence, minorCadence, harmonicMinorCadence, majorMelody, minorMelody
    }

    let signal: Material
    let rootOffset: Int

    var root: Int { 48 + rootOffset }
    var expectedKey: PitchClass { PitchClass.allCases[rootOffset] }
    var expectedScale: String {
        switch signal {
        case .majorCadence, .majorMelody: return "major"
        case .minorCadence, .harmonicMinorCadence, .minorMelody: return "minor"
        }
    }

    var testDescription: String { "\(signal.rawValue) on \(expectedKey)" }

    func samples(sampleRate: Double) -> [Float] {
        switch signal {
        case .majorCadence: return ToneSynth.majorCadence(root: root, sampleRate: sampleRate)
        case .minorCadence: return ToneSynth.minorCadence(root: root, sampleRate: sampleRate)
        case .harmonicMinorCadence:
            return ToneSynth.minorCadence(root: root, harmonicDominant: true, sampleRate: sampleRate)
        case .majorMelody: return ToneSynth.scaleMelody(root: root, minor: false, sampleRate: sampleRate)
        case .minorMelody: return ToneSynth.scaleMelody(root: root, minor: true, sampleRate: sampleRate)
        }
    }

    static let all: [AccuracyCase] = Material.allCases.flatMap { signal in
        (0..<12).map { AccuracyCase(signal: signal, rootOffset: $0) }
    }

    /// Last result of a `.cumulative` pipeline over the case's signal.
    func detect(config: AudioConfig = AudioConfig(),
                library: ProfileLibrary = .default) async throws -> KeyResult? {
        let pipeline = try AnalysisPipeline(
            source: SyntheticSource(samples: samples(sampleRate: config.sampleRate)),
            config: config,
            library: library,
            aggregation: .cumulative
        )
        var last: KeyResult?
        for try await result in try await pipeline.start() {
            last = result
        }
        return last
    }

    func isCorrect(_ result: KeyResult?) -> Bool {
        result?.key == expectedKey && result?.scaleName == expectedScale
    }
}
