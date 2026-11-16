import Foundation
import MockingBirdCore

/// Decodes an audio file (WAV, AIFF, M4A, MP3, anything `AVAudioFile` reads) and
/// delivers mono Float32 at the requested sample rate.
///
/// Any channel count is downmixed to mono and any file rate is resampled. The stream
/// finishes at end of file, or early after `stop()`. Decoding is pull-driven: a chunk is
/// decoded only when the consumer asks for the next one.
public struct AVFoundationFileSource: AudioSource {
    private let url: URL
    private let stopFlag = StopFlag()

    /// - Parameter url: the audio file to decode.
    public init(url: URL) {
        self.url = url
    }

    /// Opens the file and returns a stream of converted sample chunks.
    ///
    /// - Throws: `AudioSourceError.unknown` if the file does not exist,
    ///   `AudioSourceError.formatUnsupported` if it cannot be decoded. A read failure part
    ///   way through fails the stream with `AudioSourceError.unknown`.
    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let decoder = try AudioFileDecoder(url: url, sampleRate: sampleRate)
        let stopFlag = stopFlag
        stopFlag.reset()
        // Pull-driven: a chunk is decoded only when the consumer asks for one, so memory
        // stays bounded and stop() takes effect at the next chunk.
        return AsyncThrowingStream(unfolding: {
            guard !stopFlag.isRaised, !Task.isCancelled else { return nil }
            return try decoder.next()
        })
    }

    /// Stops decoding; the stream finishes at the next chunk request.
    public func stop() {
        stopFlag.raise()
    }
}
