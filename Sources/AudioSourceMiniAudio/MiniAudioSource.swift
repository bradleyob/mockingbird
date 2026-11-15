import CMiniAudio
import MockingBirdCore

/// Microphone capture via the vendored miniaudio C library (Linux/POSIX; also builds on macOS).
///
/// Delivers mono Float32 at the requested rate. miniaudio's callback copies into a ring
/// buffer in C; the stream pulls from it, sleeping briefly whenever it is empty. If the
/// consumer falls more than `ringSeconds` behind, frames that do not fit are dropped by the callback
/// rather than blocking the audio thread.
public final class MiniAudioSource: AudioSource {
    /// Samples per delivered chunk, at most.
    static let chunkFrames = 4096
    /// How long the stream sleeps when the ring buffer is empty.
    static let pollInterval = Duration.milliseconds(10)
    /// Ring buffer capacity.
    static let ringSeconds = 2.0

    private let deviceName: String?
    private let backend: MiniAudioBackend
    private let sessions = SessionRegistry()

    /// - Parameter deviceName: Capture device to open, matched by name. `nil` or
    ///   `"default"` selects the system default input.
    public convenience init(deviceName: String? = nil) {
        self.init(deviceName: deviceName, backend: .platformDefault)
    }

    /// Selects the backend explicitly; tests use `.null` to run without hardware.
    init(deviceName: String?, backend: MiniAudioBackend) {
        self.deviceName = deviceName
        self.backend = backend
    }

    /// Names of the capture devices miniaudio can see, in enumeration order.
    public static func inputDeviceNames() throws -> [String] {
        try inputDeviceNames(backend: .platformDefault)
    }

    static func inputDeviceNames(backend: MiniAudioBackend, capacity: Int = 64) throws(AudioSourceError) -> [String] {
        let slot = Int(MB_DEVICE_NAME_CAPACITY)
        var names = [CChar](repeating: 0, count: capacity * slot)
        var count: UInt32 = 0
        let result = mb_list_capture_devices(backend.bridgeValue, &names, UInt32(capacity), &count)
        guard result == MB_SUCCESS else {
            throw AudioSourceError.deviceUnavailable
        }
        return (0..<Int(count)).map { index in
            let bytes = names[(index * slot)..<((index + 1) * slot)].prefix { $0 != 0 }
            return String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    /// Opens and starts the device, then streams its samples until `stop()`.
    /// - Throws: `AudioSourceError.deviceUnavailable` for an unknown name or a device that
    ///   cannot be opened.
    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let session = try CaptureSession(
            backend: backend, deviceName: deviceName, sampleRate: sampleRate, ringSeconds: Self.ringSeconds)
        sessions.add(session)
        return AsyncThrowingStream {
            while true {
                guard let chunk = try session.read(maxFrames: Self.chunkFrames) else {
                    return nil
                }
                if !chunk.isEmpty {
                    return chunk
                }
                do {
                    try await Task.sleep(for: Self.pollInterval)
                } catch {
                    session.close()
                    return nil
                }
            }
        }
    }

    /// Stops the device; the stream finishes at its next pull.
    public func stop() {
        sessions.closeAll()
    }
}
