import CMiniAudio
import Foundation
import MockingBirdCore

/// Owns one running `mb_capture` (miniaudio context, device and ring buffer) and drains it.
///
/// The audio callback runs entirely in C and only writes the ring buffer; this type's lock
/// serialises the Swift side (reads versus `close()`) and is never seen by that callback.
final class CaptureSession: ClosableSession, @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    /// Creates and starts the device.
    /// - Throws: `AudioSourceError.deviceUnavailable` if the device is unknown or cannot open.
    init(backend: MiniAudioBackend, deviceName: String?, sampleRate: Double, ringSeconds: Double) throws(AudioSourceError) {
        guard sampleRate >= 1, sampleRate <= Double(UInt32.max) else {
            throw AudioSourceError.formatUnsupported
        }
        let rate = UInt32(sampleRate.rounded())
        let ringFrames = UInt32(max(4096, (sampleRate * ringSeconds).rounded()))
        var created: OpaquePointer?
        let result = mb_capture_create(backend.bridgeValue, deviceName, rate, ringFrames, &created)
        guard result == MB_SUCCESS, let created else {
            throw AudioSourceError.deviceUnavailable
        }
        let started = mb_capture_start(created)
        guard started == MB_SUCCESS else {
            mb_capture_destroy(created)
            throw AudioSourceError.deviceUnavailable
        }
        handle = created
    }

    deinit {
        close()
    }

    /// Moves captured samples into a new array.
    /// - Returns: the samples (possibly empty), or `nil` once the session is closed.
    func read(maxFrames: Int) throws(AudioSourceError) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return nil }
        var buffer = [Float](repeating: 0, count: maxFrames)
        var read: UInt32 = 0
        let result = buffer.withUnsafeMutableBufferPointer {
            mb_capture_read(handle, $0.baseAddress, UInt32($0.count), &read)
        }
        guard result == MB_SUCCESS else {
            throw AudioSourceError.deviceDisconnected
        }
        return Array(buffer.prefix(Int(read)))
    }

    /// Stops the device and frees it. Idempotent.
    func close() {
        let closing = lock.withLock {
            let current = handle
            handle = nil
            return current
        }
        guard let closing else { return }
        // mb_capture_destroy stops the device itself; a failed explicit stop changes nothing.
        _ = mb_capture_stop(closing)
        mb_capture_destroy(closing)
    }
}
