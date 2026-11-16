import Foundation
import Testing
@testable import MockingBirdCore

@Suite("RadixTwoFFT")
struct RadixTwoFFTTests {

    @Test("an impulse has a flat magnitude spectrum")
    func impulseIsFlat() {
        let fft = RadixTwoFFT(size: 1024)
        var input = [Float](repeating: 0, count: 1024)
        input[0] = 1
        let magnitudes = fft.magnitudes(of: input)

        #expect(magnitudes.count == 512)
        // Same scale as vDSP_fft_zrip: twice the mathematical DFT magnitude.
        for magnitude in magnitudes.dropFirst() {
            #expect(abs(magnitude - 2) < 1e-5)
        }
    }

    @Test("a 440 Hz sine peaks at the expected bin")
    func sinePeaksAtExpectedBin() throws {
        let size = 4096
        let sampleRate = 44100.0
        let fft = RadixTwoFFT(size: size)
        let input = (0..<size).map { Float(sin(2 * Double.pi * 440 * Double($0) / sampleRate)) }
        let magnitudes = fft.magnitudes(of: input)

        let peak = try #require(magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] })
        let expected = Int((440 * Double(size) / sampleRate).rounded())
        #expect(peak == expected)
    }

    @Test("a bin-centred sine has magnitude N on the vDSP scale")
    func binCentredSineMagnitude() {
        let size = 256
        let fft = RadixTwoFFT(size: size)
        let input = (0..<size).map { Float(sin(2 * Double.pi * 8 * Double($0) / Double(size))) }
        let magnitudes = fft.magnitudes(of: input)
        // |X[8]| = N/2 for a unit sine; vDSP scale doubles it.
        #expect(abs(magnitudes[8] - Float(size)) < 1e-3)
    }

    @Test("input shorter than the transform size is zero-padded")
    func shortInputIsZeroPadded() {
        let fft = RadixTwoFFT(size: 16)
        let padded = fft.magnitudes(of: [1, 2, 3, 4] + [Float](repeating: 0, count: 12))
        let short = fft.magnitudes(of: [1, 2, 3, 4])
        #expect(padded == short)
    }

    #if canImport(Accelerate)
    @Test("agrees with the vDSP path within 1e-3 relative on a multi-tone signal")
    func agreesWithVDSP() throws {
        let config = AudioConfig(sampleRate: 44100, windowSize: 4096)
        let processor = try FFTProcessor(config: config)
        let input = (0..<config.windowSize).map { index -> Float in
            let t = Double(index) / config.sampleRate
            let mix = sin(2 * Double.pi * 261.63 * t)
                + 0.5 * sin(2 * Double.pi * 440 * t)
                + 0.25 * sin(2 * Double.pi * 1046.5 * t)
                + 0.1 * cos(2 * Double.pi * 3000 * t)
            return Float(mix)
        }

        let vDSP = processor.process(input)
        let window = FFTProcessor.blackmanWindow(size: config.windowSize)
        let windowed = zip(input, window).map { $0 * $1 }
        let portable = RadixTwoFFT(size: config.fftSize).magnitudes(of: windowed)

        #expect(vDSP.count == portable.count)
        let peak = try #require(vDSP.max())
        // Relative to each bin, with a floor far below the Blackman sidelobes so that
        // Float32 rounding in near-empty bins does not count as disagreement.
        let floor = peak * 1e-4
        for bin in 1..<(vDSP.count) {
            let reference = max(vDSP[bin], floor)
            #expect(abs(vDSP[bin] - portable[bin]) <= 1e-3 * reference, "bin \(bin)")
        }
    }
    #endif
}
