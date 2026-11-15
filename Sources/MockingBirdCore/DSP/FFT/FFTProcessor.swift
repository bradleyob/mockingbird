import Foundation
// The single sanctioned Apple import in MockingBirdCore: vDSP where it exists, with the
// pure-Swift `RadixTwoFFT` fallback everywhere else, so Core still compiles on Linux.
#if canImport(Accelerate)
import Accelerate
#endif

/// Converts a window of PCM samples into FFT magnitude bins.
///
/// Pre-allocates all working buffers at init from `AudioConfig`.
/// `process(_:)` is a pure function — same input always produces same output.
///
/// On Apple platforms this uses `vDSP_fft_zrip` (real-signal in-place FFT): the real input
/// of N samples is packed as N/2 complex values, yielding N/2 output magnitude bins
/// (DC to Nyquist). Elsewhere it uses `RadixTwoFFT`, which returns magnitudes on the
/// same scale.
///
/// - Note: Not `Sendable` by itself; callers must ensure single-threaded access.
///   `AnalysisPipeline` satisfies this by running on a single actor.
public final class FFTProcessor {
    private let config: AudioConfig
    private let window: [Float]

    #if canImport(Accelerate)
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    // Pre-allocated working buffers
    private var windowed: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    #else
    private let transform: RadixTwoFFT
    #endif

    /// - Throws: `PipelineError.fftSetupFailed` if vDSP cannot allocate the transform.
    public init(config: AudioConfig) throws {
        self.config = config
        self.window = Self.blackmanWindow(size: config.windowSize)

        #if canImport(Accelerate)
        self.log2n = vDSP_Length(config.fftSize.trailingZeroBitCount)
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
        #else
        self.transform = RadixTwoFFT(size: config.fftSize)
        #endif
    }

    #if canImport(Accelerate)
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    #endif

    /// Applies a Blackman window and computes FFT magnitudes.
    ///
    /// - Parameter samples: Exactly `config.windowSize` PCM samples.
    /// - Returns: `config.fftSize / 2` magnitude bins (DC to Nyquist).
    public func process(_ samples: [Float]) -> [Float] {
        precondition(samples.count == config.windowSize,
                     "FFTProcessor expects \(config.windowSize) samples, got \(samples.count)")
        #if canImport(Accelerate)
        return processWithVDSP(samples)
        #else
        let windowed = (0..<samples.count).map { samples[$0] * window[$0] }
        return transform.magnitudes(of: windowed)
        #endif
    }

    /// Blackman window: w(n) = 0.42 − 0.5·cos(2πn/(N−1)) + 0.08·cos(4πn/(N−1)).
    static func blackmanWindow(size: Int) -> [Float] {
        let n = Float(size - 1)
        return (0..<size).map { i in
            let x = 2 * Float.pi * Float(i) / n
            return 0.42 - 0.5 * cos(x) + 0.08 * cos(2 * x)
        }
    }

    // MARK: - vDSP

    #if canImport(Accelerate)
    private func processWithVDSP(_ samples: [Float]) -> [Float] {
        let halfN = config.fftSize / 2

        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(config.windowSize))

        // Pack N windowed real samples into N/2 complex values (interleaved → split).
        //
        // `vDSP_ctoz` stride is in FLOAT units. Stride=2 means "read consecutive
        // DSPComplex elements" — i.e. stride of 2 floats between real parts, which is
        // the minimum valid (must be even). This produces:
        //   realp[k] = windowed[2k], imagp[k] = windowed[2k+1]
        //
        // For zero-padding: only windowSize/2 pairs are populated from `windowed`;
        // the remaining realPart[windowSize/2...] and imagPart[windowSize/2...] stay
        // at zero (pre-allocated as zeros in init).
        let packCount = vDSP_Length(config.windowSize / 2)
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
    #endif
}
