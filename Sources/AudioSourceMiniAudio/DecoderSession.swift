import CMiniAudio
import Foundation
import MockingBirdCore

/// Owns one open `mb_decoder` and reads it chunk by chunk.
final class DecoderSession: ClosableSession, @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    /// - Throws: `AudioSourceError.unknown` if the file cannot be read,
    ///   `.formatUnsupported` if miniaudio cannot decode it.
    init(url: URL, sampleRate: Double) throws(AudioSourceError) {
        guard sampleRate >= 1, sampleRate <= Double(UInt32.max) else {
            throw AudioSourceError.formatUnsupported
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw AudioSourceError.unknown("cannot read file: \(url.path)")
        }
        var opened: OpaquePointer?
        let result = mb_decoder_open(url.path, UInt32(sampleRate.rounded()), &opened)
        guard result == MB_SUCCESS, let opened else {
            throw AudioSourceError.formatUnsupported
        }
        handle = opened
    }

    deinit {
        close()
    }

    /// The next decoded samples, or `nil` at end of file or once closed (and then closes).
    func read(maxFrames: Int) throws(AudioSourceError) -> [Float]? {
        let chunk = try decodeChunk(maxFrames: maxFrames)
        if chunk == nil {
            close()
        }
        return chunk
    }

    private func decodeChunk(maxFrames: Int) throws(AudioSourceError) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return nil }
        var buffer = [Float](repeating: 0, count: maxFrames)
        var read: UInt32 = 0
        let result = buffer.withUnsafeMutableBufferPointer {
            mb_decoder_read(handle, $0.baseAddress, UInt32($0.count), &read)
        }
        guard result == MB_SUCCESS else {
            throw AudioSourceError.unknown("decoding failed: \(MiniAudioResult.describe(result))")
        }
        return read == 0 ? nil : Array(buffer.prefix(Int(read)))
    }

    /// Frees the decoder. Idempotent.
    func close() {
        let closing = lock.withLock {
            let current = handle
            handle = nil
            return current
        }
        if let closing {
            mb_decoder_close(closing)
        }
    }
}
