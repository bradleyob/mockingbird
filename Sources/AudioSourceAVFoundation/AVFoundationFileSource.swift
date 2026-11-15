import Foundation
import MockingBirdCore

/// Decodes an audio file (WAV / AIFF / M4A / MP3 / anything `AVAudioFile` reads) and
/// delivers mono Float32 at the requested sample rate.
///
/// Phase 0 contract stub — Track B (MB-20) implements the body. The public signatures
/// below are frozen: the macOS app (Track D) compiles against them.
public struct AVFoundationFileSource: AudioSource {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        throw AudioSourceError.formatUnsupported
    }

    public func stop() {}
}
