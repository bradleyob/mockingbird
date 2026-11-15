import MockingBirdCore

/// Microphone capture via the vendored miniaudio C library (Linux/POSIX; also builds on macOS).
///
/// Phase 0 contract stub — Track C (MB-11) implements the body. The public signatures
/// below are frozen: the CLI (Track B) compiles against them.
public final class MiniAudioSource: AudioSource {
    private let deviceName: String?

    /// - Parameter deviceName: Capture device to open, matched by name. `nil` or
    ///   `"default"` selects the system default input.
    public init(deviceName: String? = nil) {
        self.deviceName = deviceName
    }

    /// Names of the capture devices miniaudio can see, in enumeration order.
    public static func inputDeviceNames() throws -> [String] {
        throw AudioSourceError.deviceUnavailable
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        throw AudioSourceError.deviceUnavailable
    }

    public func stop() {}
}
