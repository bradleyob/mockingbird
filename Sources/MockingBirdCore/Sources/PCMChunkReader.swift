import Foundation

/// Reads mono Float32 little-endian PCM from a file descriptor, one bounded chunk per call.
///
/// Uses `read(2)` directly so a pipe delivers whatever is available instead of blocking
/// until a full chunk arrives, which keeps live stdin input flowing. Bytes that do not
/// complete a sample are carried into the next read, so odd-sized pipe writes never
/// misalign later samples. A trailing partial sample at end of input is dropped.
///
/// Pull-based: `AudioSource` implementations wrap `nextChunk()` in
/// `AsyncThrowingStream(unfolding:)`, so the file is read only as fast as it is consumed.
/// `nextChunk()` is called serially by the stream's iterator; only the stop flag is
/// touched from other threads, and it is lock-protected.
final class PCMChunkReader: @unchecked Sendable {
    private let handle: FileHandle
    private let chunkBytes: Int
    private let stopLock = NSLock()
    private var stopped = false
    private var pending: [UInt8] = []
    private var readBuffer: [UInt8]

    /// - Parameters:
    ///   - handle: Source of bytes. Kept open (and alive) for the reader's lifetime.
    ///   - chunkSamples: Maximum samples returned per chunk; at least 1.
    init(handle: FileHandle, chunkSamples: Int) {
        precondition(chunkSamples >= 1, "chunkSamples must be at least 1, got \(chunkSamples)")
        self.handle = handle
        self.chunkBytes = chunkSamples * MemoryLayout<Float>.size
        self.readBuffer = [UInt8](repeating: 0, count: chunkBytes)
    }

    /// Makes later `nextChunk()` calls return `nil`.
    func stop() {
        stopLock.withLock { stopped = true }
    }

    private var isStopped: Bool {
        stopLock.withLock { stopped }
    }

    /// The next chunk of samples, or `nil` at end of input or after `stop()`.
    ///
    /// - Throws: `AudioSourceError.unknown` if the read fails.
    func nextChunk() throws -> [Float]? {
        while !isStopped && !Task.isCancelled {
            let count = try readSome()
            guard count > 0 else { return nil }
            pending.append(contentsOf: readBuffer[0..<count])
            let whole = pending.count / 4
            guard whole > 0 else { continue }
            let samples = (0..<whole).map { index -> Float in
                let base = index * 4
                let bits = UInt32(pending[base])
                    | UInt32(pending[base + 1]) << 8
                    | UInt32(pending[base + 2]) << 16
                    | UInt32(pending[base + 3]) << 24
                return Float(bitPattern: bits)
            }
            pending.removeFirst(whole * 4)
            return samples
        }
        return nil
    }

    /// Reads up to `chunkBytes - pending.count` bytes into `readBuffer`; 0 means end of input.
    private func readSome() throws -> Int {
        let wanted = max(1, chunkBytes - pending.count)
        let descriptor = handle.fileDescriptor
        while true {
            let result = readBuffer.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return read(descriptor, base, wanted)
            }
            if result >= 0 { return result }
            let code = errno
            if code == EINTR { continue }
            throw AudioSourceError.unknown("read failed: \(String(cString: strerror(code)))")
        }
    }
}
