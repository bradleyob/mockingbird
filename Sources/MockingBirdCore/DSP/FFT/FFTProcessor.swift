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
        let packCount = config.windowSize / 2
        var magnitudes = [Float](repeating: 0, count: halfN)

        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(config.windowSize))

        windowed.withUnsafeBufferPointer { windowedBuffer in
            realPart.withUnsafeMutableBufferPointer { realBuffer in
                imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                    magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                        guard let windowedBase = windowedBuffer.baseAddress,
                              let real = realBuffer.baseAddress,
                              let imag = imagBuffer.baseAddress,
                              let output = magnitudeBuffer.baseAddress,
                              packCount > 0 else { return }

                        // The in-place FFT overwrites the whole split buffer, including the
                        // zero-padded upper half, so that half must be cleared on every call
                        // or one window's spectrum leaks into the next.
                        let padding = vDSP_Length(halfN - packCount)
                        if padding > 0 {
                            vDSP_vclr(real + packCount, 1, padding)
                            vDSP_vclr(imag + packCount, 1, padding)
                        }

                        var split = DSPSplitComplex(realp: real, imagp: imag)
                        // Pack N real samples as N/2 complex values: realp[k] = x[2k],
                        // imagp[k] = x[2k+1]. The stride is in Float units, so 2 = adjacent pairs.
                        windowedBase.withMemoryRebound(to: DSPComplex.self, capacity: packCount) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(packCount))
                        }
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, output, 1, vDSP_Length(halfN))
                    }
                }
            }
        }

        return magnitudes
    }
    #endif
}
