import Foundation

/// Maps FFT magnitude bins to a 12-bin chroma vector using spectral peaks only.
///
/// Summing every bin into chroma smears each partial over its window's main lobe
/// (about ±2 semitones at C4 for a 4096-sample Blackman window), so low notes land on
/// the wrong pitch class. Instead, only local maxima above `peakThreshold` of the
/// window's strongest magnitude contribute; each peak's frequency is refined by
/// parabolic interpolation on log magnitude, folded to a pitch class, and its magnitude
/// is added to that class. Frequencies outside 65–2000 Hz are ignored.
///
/// `extractEnergy(_:)` returns the raw (un-normalised) chroma, so callers aggregating
/// several windows weight loud windows more; `extract(_:)` is its L2-normalised form.
/// Both are pure functions — no internal mutable state.
public struct ChromaExtractor: Sendable {
    /// Lowest frequency (Hz) that contributes to chroma.
    public static let minimumFrequency = 65.0
    /// Highest frequency (Hz) that contributes to chroma.
    public static let maximumFrequency = 2000.0
    /// A peak must exceed this fraction of the window's maximum magnitude.
    public static let peakThreshold: Float = 0.02

    private let config: AudioConfig
    private let binWidth: Double
    /// Candidate peak bins: those whose neighbours both exist and that can fall in range.
    private let searchRange: Range<Int>

    public init(config: AudioConfig) {
        self.config = config
        self.binWidth = config.sampleRate / Double(config.fftSize)
        let binCount = config.fftSize / 2
        let lowest = max(1, Int((Self.minimumFrequency / binWidth).rounded(.down)) - 1)
        let highest = min(binCount - 2, Int((Self.maximumFrequency / binWidth).rounded(.up)) + 1)
        self.searchRange = lowest..<max(lowest, highest + 1)
    }

    /// Maps FFT magnitudes to an L2-normalised `ChromaVector` (all zeros for silence).
    ///
    /// - Parameter magnitudes: Output of `FFTProcessor.process(_:)`, count = `config.fftSize / 2`.
    public func extract(_ magnitudes: [Float]) -> ChromaVector {
        normalized(extractEnergy(magnitudes))
    }

    /// Un-normalised 12-bin chroma energy (index 0 = C) of one window.
    ///
    /// - Parameter magnitudes: Output of `FFTProcessor.process(_:)`, count = `config.fftSize / 2`.
    public func extractEnergy(_ magnitudes: [Float]) -> [Float] {
        precondition(magnitudes.count == config.fftSize / 2,
                     "ChromaExtractor expects \(config.fftSize / 2) magnitudes, got \(magnitudes.count)")

        var energy = [Float](repeating: 0, count: 12)
        let strongest = magnitudes[searchRange].max() ?? 0
        guard strongest > 0 else { return energy }
        let threshold = strongest * Self.peakThreshold

        for bin in searchRange {
            let magnitude = magnitudes[bin]
            guard magnitude > threshold,
                  magnitude > magnitudes[bin - 1],
                  magnitude >= magnitudes[bin + 1] else { continue }

            let frequency = (Double(bin) + peakOffset(magnitudes[bin - 1], magnitude, magnitudes[bin + 1])) * binWidth
            guard frequency >= Self.minimumFrequency, frequency <= Self.maximumFrequency else { continue }
            energy[Self.pitchClassIndex(frequency: frequency)] += magnitude
        }
        return energy
    }

    /// Wraps chroma energy as an L2-normalised `ChromaVector`. All-zero energy stays zero.
    public func normalized(_ energy: [Float]) -> ChromaVector {
        let norm = energy.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let bins = norm > 0 ? energy.map { $0 / norm } : energy
        return ChromaVector(bins: bins, sampleRate: config.sampleRate, windowSize: config.windowSize)
    }

    // MARK: - Private

    /// Fractional bin offset of a peak in (-0.5, 0.5), from a parabola through the
    /// log magnitudes of the peak bin and its neighbours.
    private func peakOffset(_ left: Float, _ centre: Float, _ right: Float) -> Double {
        let tiny: Float = 1e-12
        let a = Double(log(max(left, tiny)))
        let b = Double(log(max(centre, tiny)))
        let c = Double(log(max(right, tiny)))
        let denominator = a - 2 * b + c
        guard denominator < 0 else { return 0 }
        return min(0.5, max(-0.5, 0.5 * (a - c) / denominator))
    }

    /// Pitch class (0 = C) nearest to `frequency`, with A4 = 440 Hz = MIDI 69.
    private static func pitchClassIndex(frequency: Double) -> Int {
        let midi = 12 * log2(frequency / 440) + 69
        return (Int(midi.rounded()) % 12 + 12) % 12
    }
}
