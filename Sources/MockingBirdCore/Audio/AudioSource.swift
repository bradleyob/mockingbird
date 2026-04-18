/// A platform-agnostic audio capture source.
///
/// Implementations deliver raw PCM samples as `[Float]` chunks via an
/// `AsyncThrowingStream`. The stream throws `AudioSourceError` on failure.
///
/// All implementations follow the `[Platform]Source` naming convention:
/// `AVFoundationSource`, `MiniAudioSource`, `FileSource`, `RawPCMSource`.
public protocol AudioSource: Sendable {
    /// Starts capture and returns a stream of PCM sample chunks.
    ///
    /// Each chunk is a contiguous array of interleaved or mono Float32 samples
    /// at the given sample rate. The stream ends (cleanly) when `stop()` is called
    /// or throws `AudioSourceError` on failure.
    func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error>

    /// Signals the source to stop producing samples and finish the stream.
    func stop()
}
