/// A 12-bin, L2-normalized chroma vector representing pitch class energy.
///
/// Index 0 = C, index 11 = B. Produced by `ChromaExtractor` from FFT spectral peaks.
/// Silence gives all-zero bins.
public struct ChromaVector: Equatable, Codable, Sendable {
    /// 12 pitch class energy bins. Count is always exactly 12.
    public let bins: [Float]
    public let sampleRate: Double
    public let windowSize: Int

    public init(bins: [Float], sampleRate: Double, windowSize: Int) {
        precondition(bins.count == 12, "ChromaVector bins count must be 12, got \(bins.count)")
        self.bins = bins
        self.sampleRate = sampleRate
        self.windowSize = windowSize
    }

    /// Returns the energy for the given pitch class.
    public subscript(pitchClass: PitchClass) -> Float {
        bins[pitchClass.rawValue]
    }
}
