@preconcurrency import AVFoundation
import MockingBirdCore

/// Converts input-node tap buffers to mono Float32 at the analysis rate.
///
/// The `AVAudioConverter` and its output buffer are built once, before capture starts,
/// rather than inside every tap callback.
///
/// `@unchecked Sendable`: after `init` an instance is used only from the input node's tap
/// block, which AVAudioEngine calls serially.
final class TapConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputBuffer: AVAudioPCMBuffer
    private let maxInputFrames: AVAudioFrameCount
    /// The tap buffer not yet handed to the converter during the current `convert` call.
    private var pendingInput: AVAudioPCMBuffer?

    /// - Parameters:
    ///   - inputFormat: the input node's output format.
    ///   - sampleRate: the rate the stream delivers.
    ///   - maxInputFrames: the largest tap buffer that will be converted.
    /// - Throws: `AudioSourceError.formatUnsupported` if no converter exists for the formats.
    init(inputFormat: AVAudioFormat, sampleRate: Double, maxInputFrames: AVAudioFrameCount) throws(AudioSourceError) {
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(
                    (Double(maxInputFrames) * sampleRate / inputFormat.sampleRate).rounded(.up)
                ) + 64
            )
        else {
            throw .formatUnsupported
        }
        converter.downmix = true
        self.converter = converter
        self.outputBuffer = outputBuffer
        self.maxInputFrames = maxInputFrames
    }

    /// Converts one tap buffer. The resampler keeps its state between calls, so
    /// consecutive buffers join without discontinuities.
    func convert(_ buffer: AVAudioPCMBuffer) -> Result<[Float], AudioSourceError> {
        guard buffer.frameLength <= maxInputFrames else {
            return .failure(.unknown("tap buffer of \(buffer.frameLength) frames exceeds \(maxInputFrames)"))
        }
        outputBuffer.frameLength = 0
        pendingInput = buffer
        defer { pendingInput = nil }
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { [self] _, inputStatus in
            // Hand over this buffer once, then report "no data yet" (not end of stream),
            // so the converter keeps its resampling state for the next tap buffer.
            guard let input = pendingInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            pendingInput = nil
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = outputBuffer.floatChannelData?[0] else {
            return .failure(.unknown(conversionError?.localizedDescription ?? "audio conversion failed"))
        }
        return .success(Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength))))
    }
}
