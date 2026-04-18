/// Configuration for the audio capture and DSP pipeline.
///
/// Passed at initialization time; all DSP components pre-allocate their
/// buffers from these values. Treat as immutable after construction.
public struct AudioConfig: Equatable, Codable, Sendable {
    /// Sample rate in Hz. Must be > 0.
    public let sampleRate: Double
    /// FFT window size in samples. Must be a power of two.
    public let windowSize: Int
    /// Hop size in samples (overlap = windowSize - hopSize). Must be > 0 and ≤ windowSize.
    public let hopSize: Int
    /// Number of alternate key candidates to include in `KeyResult`.
    public let numAlternates: Int
    /// Whether the FFT input should be zero-padded to 2× window size before transform.
    public let zeroPad: Bool

    public init(
        sampleRate: Double = 44100,
        windowSize: Int = 4096,
        hopSize: Int = 2048,
        numAlternates: Int = 3,
        zeroPad: Bool = false
    ) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        precondition(windowSize > 0 && (windowSize & (windowSize - 1)) == 0,
                     "windowSize must be a power of two")
        precondition(hopSize > 0 && hopSize <= windowSize,
                     "hopSize must be in (0, windowSize]")
        precondition(numAlternates >= 0, "numAlternates must be non-negative")
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.hopSize = hopSize
        self.numAlternates = numAlternates
        self.zeroPad = zeroPad
    }

    /// FFT size after optional zero-padding.
    public var fftSize: Int { zeroPad ? windowSize * 2 : windowSize }
}
