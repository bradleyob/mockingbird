import Foundation
import MockingBirdCore

/// Decodes an audio file (WAV / FLAC / MP3) with miniaudio's built-in decoders and
/// delivers mono Float32 at the requested sample rate.
///
/// Phase 0 contract stub — Track C (MB-20) implements the body. The public signatures
/// below are frozen: the CLI (Track B) compiles against them on Linux.
public struct MiniAudioFileSource: AudioSource {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        throw AudioSourceError.formatUnsupported
    }

    public func stop() {}
}
