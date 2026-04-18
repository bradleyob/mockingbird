import Accelerate

/// Maps FFT magnitude bins to a 12-bin L2-normalized `ChromaVector`.
///
/// Each FFT bin is mapped to a pitch class by its center frequency,
/// restricted to 65–2000 Hz to reduce noise and overtone contamination.
/// Multiple octaves of the same pitch class are accumulated (octave folding).
/// The result is L2-normalized.
///
/// `extract(_:)` is a pure function — no internal mutable state.
public struct ChromaExtractor {
    private let config: AudioConfig
    /// Pre-computed mapping: FFT bin index → pitch class index (0–11), or -1 to skip.
    private let binToPitchClass: [Int]

    public init(config: AudioConfig) {
        self.config = config
        self.binToPitchClass = Self.buildBinMap(
            fftSize: config.fftSize,
            sampleRate: config.sampleRate,
            minHz: 65.0,
            maxHz: 2000.0
        )
    }

    /// Maps FFT magnitudes to a `ChromaVector`.
    ///
    /// - Parameter magnitudes: Output of `FFTProcessor.process(_:)`, count = `config.fftSize / 2`.
    /// - Returns: L2-normalized 12-bin chroma vector.
    public func extract(_ magnitudes: [Float]) -> ChromaVector {
        precondition(magnitudes.count == config.fftSize / 2,
                     "ChromaExtractor expects \(config.fftSize / 2) magnitudes, got \(magnitudes.count)")

        var bins = [Float](repeating: 0, count: 12)

        for (binIndex, pitchClass) in binToPitchClass.enumerated() where pitchClass >= 0 {
            bins[pitchClass] += magnitudes[binIndex]
        }

        // L2 normalize
        var sumOfSquares: Float = 0
        vDSP_svesq(bins, 1, &sumOfSquares, vDSP_Length(12))
        let norm = sumOfSquares.squareRoot()
        if norm > 0 {
            var normValue = norm
            vDSP_vsdiv(bins, 1, &normValue, &bins, 1, 12)
        }

        return ChromaVector(bins: bins, sampleRate: config.sampleRate, windowSize: config.windowSize)
    }

    // MARK: - Private

    private static func buildBinMap(
        fftSize: Int,
        sampleRate: Double,
        minHz: Double,
        maxHz: Double
    ) -> [Int] {
        let numBins = fftSize / 2
        let binWidth = sampleRate / Double(fftSize)
        // A4 = 440 Hz, MIDI note 69
        let a4Hz = 440.0
        let a4Midi = 69.0

        return (0..<numBins).map { bin in
            let freq = Double(bin) * binWidth
            guard freq >= minHz && freq <= maxHz else { return -1 }
            // Convert frequency to MIDI note number
            let midi = 12.0 * log2(freq / a4Hz) + a4Midi
            // Pitch class = MIDI mod 12, with C=0
            let pitchClass = (Int(midi.rounded()) % 12 + 12) % 12
            return pitchClass
        }
    }
}
