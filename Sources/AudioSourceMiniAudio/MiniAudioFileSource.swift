import Foundation
import MockingBirdCore

/// Decodes an audio file (WAV / FLAC / MP3) with miniaudio's built-in decoders and
/// delivers mono Float32 at the requested sample rate (downmixed and resampled).
///
/// The stream is pull-based: the file is decoded one chunk per element as the consumer asks,
/// so memory stays flat and `stop()` takes effect on the next pull.
public struct MiniAudioFileSource: AudioSource {
    /// Samples per delivered chunk, at most.
    static let chunkFrames = 4096

    private let url: URL
    private let sessions = SessionRegistry()

    public init(url: URL) {
        self.url = url
    }

    /// - Throws: `AudioSourceError.unknown` if the file cannot be read,
    ///   `.formatUnsupported` if it cannot be decoded.
    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let session = try DecoderSession(url: url, sampleRate: sampleRate)
        sessions.add(session)
        return AsyncThrowingStream {
            try session.read(maxFrames: Self.chunkFrames)
        }
    }

    /// Closes the decoder; the stream finishes at its next pull.
    public func stop() {
        sessions.closeAll()
    }
}
