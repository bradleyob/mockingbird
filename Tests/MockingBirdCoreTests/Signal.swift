import Foundation

/// Small signal helpers shared by the Core tests (ToneSynth covers musical material).
enum Signal {
    /// A unit-amplitude sine of `count` samples.
    static func sine(frequency: Double, sampleRate: Double = 44100, count: Int) -> [Float] {
        (0..<count).map { Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    /// Index of the largest element.
    static func argmax(_ values: [Float]) -> Int? {
        values.indices.max { values[$0] < values[$1] }
    }
}
