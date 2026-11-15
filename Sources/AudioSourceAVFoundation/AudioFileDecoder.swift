@preconcurrency import AVFoundation
import MockingBirdCore

/// Pulls an audio file through `AVAudioConverter` as mono Float32 at a target rate,
/// one chunk at a time.
///
/// `@unchecked Sendable`: an instance is created by `AVFoundationFileSource.start` and
/// then driven only by that stream's unfolding closure, which the stream calls serially.
final class AudioFileDecoder: @unchecked Sendable {
    /// Input frames read from the file per conversion step.
    static let chunkFrames: AVAudioFrameCount = 8192

    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let inputBuffer: AVAudioPCMBuffer
    private let outputBuffer: AVAudioPCMBuffer
    private var inputExhausted = false
    private var finished = false
    private var readError: Error?

    /// Opens `url` for decoding.
    ///
    /// - Throws: `AudioSourceError.unknown` if the file does not exist,
    ///   `AudioSourceError.formatUnsupported` if it cannot be decoded or converted.
    init(url: URL, sampleRate: Double) throws(AudioSourceError) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw .unknown("no such file: \(url.path)")
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw .formatUnsupported
        }
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
            ),
            let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat),
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: Self.chunkFrames),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(
                    (Double(Self.chunkFrames) * sampleRate / file.processingFormat.sampleRate).rounded(.up)
                ) + 64
            )
        else {
            throw .formatUnsupported
        }
        // Without this the converter keeps only the first channel when going to mono.
        converter.downmix = true
        self.file = file
        self.converter = converter
        self.inputBuffer = inputBuffer
        self.outputBuffer = outputBuffer
    }

    /// The next chunk of converted samples, or `nil` at end of file.
    ///
    /// - Throws: `AudioSourceError.unknown` if reading or converting fails.
    func next() throws(AudioSourceError) -> [Float]? {
        while !finished {
            outputBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { [self] _, inputStatus in
                provideInput(inputStatus)
            }
            if let readError {
                throw .unknown("cannot read audio file: \(readError.localizedDescription)")
            }
            switch status {
            case .error:
                throw .unknown("audio conversion failed: \(conversionError?.localizedDescription ?? "unknown error")")
            case .endOfStream:
                finished = true
            case .haveData, .inputRanDry:
                break
            @unknown default:
                break
            }
            let frames = Int(outputBuffer.frameLength)
            if frames > 0, let channel = outputBuffer.floatChannelData?[0] {
                return Array(UnsafeBufferPointer(start: channel, count: frames))
            }
        }
        return nil
    }

    // MARK: - Private

    private func provideInput(_ inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !inputExhausted, file.framePosition < file.length else {
            inputExhausted = true
            inputStatus.pointee = .endOfStream
            return nil
        }
        do {
            try file.read(into: inputBuffer, frameCount: Self.chunkFrames)
        } catch {
            readError = error
            inputExhausted = true
            inputStatus.pointee = .endOfStream
            return nil
        }
        guard inputBuffer.frameLength > 0 else {
            inputExhausted = true
            inputStatus.pointee = .endOfStream
            return nil
        }
        inputStatus.pointee = .haveData
        return inputBuffer
    }
}
