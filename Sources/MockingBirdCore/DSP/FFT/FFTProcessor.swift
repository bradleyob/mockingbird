import Accelerate

/// Converts a window of PCM samples into FFT magnitude bins.
///
/// Pre-allocates all working buffers at init from `AudioConfig`.
/// `process(_:)` is a pure function — same input always produces same output.
/// All state is held in pre-allocated buffers; the call itself does not allocate.
///
/// Uses `vDSP_fft_zrip` (real-signal in-place FFT) for maximum efficiency.
/// The real input of N samples is packed as N/2 complex values, yielding
/// N/2 output magnitude bins (DC to Nyquist).
///
/// - Note: Not `Sendable` by itself; callers must ensure single-threaded access.
///   `AnalysisPipeline` satisfies this by running on a single actor.
public final class FFTProcessor {
    private let config: AudioConfig
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    // Pre-allocated working buffers
    private var windowed: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private let window: [Float]

    /// - Throws: `PipelineError.fftSetupFailed` if vDSP cannot allocate the transform.
    public init(config: AudioConfig) throws {
        self.config = config
        self.log2n = vDSP_Length(log2(Double(config.fftSize)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw PipelineError.fftSetupFailed(ErrorContext(
                operation: "vDSP_create_fftsetup",
                component: "FFTProcessor"
            ))
        }
        self.fftSetup = setup

        let halfN = config.fftSize / 2
        self.windowed = [Float](repeating: 0, count: config.windowSize)
        self.realPart = [Float](repeating: 0, count: halfN)
        self.imagPart = [Float](repeating: 0, count: halfN)
        self.window   = Self.blackmanWindow(size: config.windowSize)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Applies a Blackman window and computes FFT magnitudes.
    ///
    /// - Parameter samples: Exactly `config.windowSize` PCM samples.
    /// - Returns: `config.fftSize / 2` magnitude bins (DC to Nyquist).
    public func process(_ samples: [Float]) -> [Float] {
        precondition(samples.count == config.windowSize,
                     "FFTProcessor expects \(config.windowSize) samples, got \(samples.count)")

        let halfN = config.fftSize / 2

        // Apply Blackman window
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(config.windowSize))

        // Pack N windowed real samples into N/2 complex values (interleaved → split).
        // If zero-padding: windowed has windowSize samples; the upper half of the
        // virtual N-sample frame is zeros — we only pack windowSize/2 pairs from
        // windowed and leave realPart[windowSize/2...] and imagPart[windowSize/2...] as 0.
        let packCount = vDSP_Length(min(halfN, config.windowSize / 2))
        windowed.withUnsafeBufferPointer { wPtr in
            wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Int(packCount)) { cPtr in
                realPart.withUnsafeMutableBufferPointer { rBuf in
                    imagPart.withUnsafeMutableBufferPointer { iBuf in
                        var sc = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                        vDSP_ctoz(cPtr, 2, &sc, 1, packCount)
                    }
                }
            }
        }

        // In-place real FFT
        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeMutableBufferPointer { rBuf in
            imagPart.withUnsafeMutableBufferPointer { iBuf in
                var sc = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                vDSP_fft_zrip(fftSetup, &sc, 1, log2n, FFTDirection(FFT_FORWARD))

                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    vDSP_zvabs(&sc, 1, magBuf.baseAddress!, 1, vDSP_Length(halfN))
                }
            }
        }

        return magnitudes
    }

    // MARK: - Private

    private static func blackmanWindow(size: Int) -> [Float] {
        // w(n) = 0.42 − 0.5·cos(2πn/(N−1)) + 0.08·cos(4πn/(N−1))
        var w = [Float](repeating: 0, count: size)
        let n = Float(size - 1)
        for i in 0..<size {
            let x = 2 * Float.pi * Float(i) / n
            w[i] = 0.42 - 0.5 * cos(x) + 0.08 * cos(2 * x)
        }
        return w
    }
}
