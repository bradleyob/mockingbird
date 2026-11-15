#if os(macOS)
import AVFoundation
@testable import AudioSourceAVFoundation
import MockingBirdCore
import Testing

/// The capture conversion path, fed synthetic buffers (no device, no permission prompt).
@Suite struct TapConverterTests {
    private func stereoBuffer(frames: AVAudioFrameCount, sampleRate: Double, startFrame: Int) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try #require(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            let value = Float(sin(2 * Double.pi * 440 * Double(startFrame + frame) / sampleRate)) * 0.5
            channels[0][frame] = value
            channels[1][frame] = value
        }
        return buffer
    }

    @Test func resamplesAndDownmixesConsecutiveBuffers() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let converter = try TapConverter(inputFormat: input, sampleRate: 44100, maxInputFrames: 4800)
        var total = 0
        var peak: Float = 0
        for index in 0..<50 {
            let buffer = try stereoBuffer(frames: 4800, sampleRate: 48000, startFrame: index * 4800)
            let samples = try converter.convert(buffer).get()
            total += samples.count
            peak = max(peak, samples.map(abs).max() ?? 0)
        }
        // 5 s of 48 kHz input → about 220500 samples at 44.1 kHz (the resampler holds back a few).
        #expect(abs(Double(total) - 220_500) < 220_500 * 0.01, "got \(total)")
        // Downmixing two identical channels must not clip or drop the signal.
        #expect(peak > 0.3 && peak <= 1.0, "peak \(peak)")
    }

    @Test func rejectsOversizedBuffer() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let converter = try TapConverter(inputFormat: input, sampleRate: 44100, maxInputFrames: 1024)
        let buffer = try stereoBuffer(frames: 2048, sampleRate: 44100, startFrame: 0)
        #expect(throws: AudioSourceError.self) { try converter.convert(buffer).get() }
    }
}
#endif
