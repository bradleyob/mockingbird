import MockingBirdCore

/// Stub: Linux/POSIX microphone capture via the vendored miniaudio C library.
///
/// Full implementation will call `mb_device_init` / `mb_device_start` via the
/// C bridge in `Sources/AudioSourceMiniAudio/miniaudio_bridge.c`.
/// The data callback posts chunks to the stream continuation via a lock-free ring buffer
/// pre-allocated at init so the callback path never allocates.
public final class MiniAudioSource: AudioSource {
    public init() {}

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        // TODO: MB-11 — implement miniaudio device init and real-time callback bridge
        throw AudioSourceError.deviceUnavailable
    }

    public func stop() {
        // TODO: MB-11 — stop and destroy ma_device
    }
}
