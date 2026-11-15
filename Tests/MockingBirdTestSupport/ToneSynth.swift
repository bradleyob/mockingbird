import Foundation

/// Deterministic test-signal generator. Notes are MIDI numbers (60 = C4, 69 = A4 = 440 Hz).
///
/// Every note is rendered as a fundamental plus `harmonics - 1` overtones at 1/h amplitude,
/// with a short fade in/out so that concatenated notes do not click.
public enum ToneSynth {
    public static let majorSteps = [0, 2, 4, 5, 7, 9, 11]
    public static let naturalMinorSteps = [0, 2, 3, 5, 7, 8, 10]

    public static func frequency(midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    /// Simultaneous notes (a chord, or a single tone) lasting `duration` seconds, peak-normalized.
    public static func chord(
        _ notes: [Int],
        harmonics: Int = 3,
        sampleRate: Double = 44100,
        duration: Double = 1.0
    ) -> [Float] {
        let count = Int(sampleRate * duration)
        guard count > 0, !notes.isEmpty else { return [] }
        var samples = [Float](repeating: 0, count: count)
        for note in notes {
            let fundamental = frequency(midi: note)
            for harmonic in 1...max(harmonics, 1) {
                let step = 2 * Double.pi * fundamental * Double(harmonic) / sampleRate
                let amplitude = 1 / Double(harmonic)
                for index in 0..<count {
                    samples[index] += Float(amplitude * sin(step * Double(index)))
                }
            }
        }
        let peak = samples.map(abs).max() ?? 0
        if peak > 0 {
            samples = samples.map { $0 / peak }
        }
        let fade = min(400, count / 4)
        for index in 0..<fade {
            let gain = Float(index) / Float(fade)
            samples[index] *= gain
            samples[count - 1 - index] *= gain
        }
        return samples
    }

    /// Chords played one after another, `chordDuration` seconds each.
    public static func progression(
        _ chords: [[Int]],
        harmonics: Int = 3,
        sampleRate: Double = 44100,
        chordDuration: Double = 1.0
    ) -> [Float] {
        chords.flatMap { chord($0, harmonics: harmonics, sampleRate: sampleRate, duration: chordDuration) }
    }

    /// Single notes played one after another, `noteDuration` seconds each.
    public static func melody(
        _ notes: [Int],
        harmonics: Int = 4,
        sampleRate: Double = 44100,
        noteDuration: Double = 0.25
    ) -> [Float] {
        notes.flatMap { chord([$0], harmonics: harmonics, sampleRate: sampleRate, duration: noteDuration) }
    }

    /// Root-position triad on `root`.
    public static func triad(root: Int, minor: Bool) -> [Int] {
        [root, root + (minor ? 3 : 4), root + 7]
    }

    /// I–IV–V–I in the major key on `root` (4 s at the default chord duration).
    public static func majorCadence(root: Int, sampleRate: Double = 44100) -> [Float] {
        progression(
            [triad(root: root, minor: false), triad(root: root + 5, minor: false),
             triad(root: root + 7, minor: false), triad(root: root, minor: false)],
            sampleRate: sampleRate
        )
    }

    /// i–iv–v–i (natural minor) or i–iv–V–i (`harmonicDominant`) on `root`.
    public static func minorCadence(
        root: Int,
        harmonicDominant: Bool = false,
        sampleRate: Double = 44100
    ) -> [Float] {
        progression(
            [triad(root: root, minor: true), triad(root: root + 5, minor: true),
             triad(root: root + 7, minor: !harmonicDominant), triad(root: root, minor: true)],
            sampleRate: sampleRate
        )
    }

    /// One octave up and back down the scale starting an octave above `root`, then the
    /// tonic triad arpeggiated (5 s at the default note duration).
    public static func scaleMelody(root: Int, minor: Bool, sampleRate: Double = 44100) -> [Float] {
        let steps = minor ? naturalMinorSteps : majorSteps
        let ascending = steps.map { root + 12 + $0 }
        let arpeggio = [root + 12, root + (minor ? 15 : 16), root + 19, root + 12]
        return melody(ascending + [root + 24] + ascending.reversed() + arpeggio, sampleRate: sampleRate)
    }
}
