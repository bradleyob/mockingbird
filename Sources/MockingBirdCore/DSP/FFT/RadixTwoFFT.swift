import Foundation

/// Portable iterative radix-2 FFT of a real signal, in pure Swift.
///
/// Used by `FFTProcessor` where Accelerate is unavailable (Linux). Magnitudes are on the
/// same scale as `vDSP_fft_zrip` followed by `vDSP_zvabs`: twice the mathematical DFT
/// magnitude, so both paths feed `ChromaExtractor` identical numbers.
///
/// Twiddle factors and the bit-reversal permutation are computed once at init.
/// `magnitudes(of:)` is a pure function; it keeps no state between calls.
public struct RadixTwoFFT: Sendable {
    /// Transform length. A power of two.
    public let size: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReversed: [Int]

    /// - Parameter size: Transform length; must be a power of two and at least 2.
    public init(size: Int) {
        precondition(size >= 2 && (size & (size - 1)) == 0,
                     "RadixTwoFFT size must be a power of two >= 2, got \(size)")
        self.size = size
        let half = size / 2
        self.cosTable = (0..<half).map { cos(2 * Double.pi * Double($0) / Double(size)) }
        self.sinTable = (0..<half).map { -sin(2 * Double.pi * Double($0) / Double(size)) }
        let bits = size.trailingZeroBitCount
        self.bitReversed = (0..<size).map { index in
            (0..<bits).reduce(0) { reversed, bit in (reversed << 1) | ((index >> bit) & 1) }
        }
    }

    /// Magnitude spectrum of `input`, zero-padded to `size` if shorter.
    ///
    /// - Parameter input: At most `size` real samples.
    /// - Returns: `size / 2` magnitudes for bins 0 (DC) … `size / 2 - 1`, scaled by 2.
    public func magnitudes(of input: [Float]) -> [Float] {
        precondition(input.count <= size,
                     "RadixTwoFFT input has \(input.count) samples, transform size is \(size)")

        var real = [Double](repeating: 0, count: size)
        var imag = [Double](repeating: 0, count: size)
        for index in 0..<input.count {
            real[bitReversed[index]] = Double(input[index])
        }

        var span = 2
        while span <= size {
            let halfSpan = span / 2
            let twiddleStride = size / span
            var start = 0
            while start < size {
                for offset in 0..<halfSpan {
                    let wr = cosTable[offset * twiddleStride]
                    let wi = sinTable[offset * twiddleStride]
                    let upper = start + offset
                    let lower = upper + halfSpan
                    let tr = wr * real[lower] - wi * imag[lower]
                    let ti = wr * imag[lower] + wi * real[lower]
                    real[lower] = real[upper] - tr
                    imag[lower] = imag[upper] - ti
                    real[upper] += tr
                    imag[upper] += ti
                }
                start += span
            }
            span *= 2
        }

        return (0..<(size / 2)).map { bin in
            Float(2 * (real[bin] * real[bin] + imag[bin] * imag[bin]).squareRoot())
        }
    }
}
