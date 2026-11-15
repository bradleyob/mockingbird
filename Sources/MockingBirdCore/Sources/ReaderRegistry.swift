import Foundation

/// Tracks the `PCMChunkReader` of a source's current stream so that the source's
/// `stop()` (which may come from any thread) reaches it. Shared by copies of the source.
final class ReaderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var current: PCMChunkReader?

    /// Makes `reader` current, stopping the previous one.
    func replace(with reader: PCMChunkReader) {
        let previous = lock.withLock { () -> PCMChunkReader? in
            defer { current = reader }
            return current
        }
        previous?.stop()
    }

    /// Stops the current reader, if any.
    func stopCurrent() {
        lock.withLock { current }?.stop()
    }
}
