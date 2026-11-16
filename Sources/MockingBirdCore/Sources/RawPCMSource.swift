import Foundation

/// Reads raw PCM samples from a `FileHandle` (stdin or any file descriptor).
///
/// Input is mono Float32 little-endian. Use this to pipe PCM data into the
/// `mockingbird` CLI via stdin: `ffmpeg -i song.mp3 -f f32le -ar 44100 -ac 1 - | mockingbird`.
/// The stream finishes at end of input or after `stop()`; the handle is never closed.
public struct RawPCMSource: AudioSource {
    private let handle: FileHandle
    /// Maximum number of Float32 samples per chunk.
    private let chunkSize: Int
    private let readers = ReaderRegistry()

    /// - Parameters:
    ///   - handle: Where to read PCM bytes from. Defaults to standard input.
    ///   - chunkSize: Maximum samples per delivered chunk; at least 1.
    public init(handle: FileHandle = .standardInput, chunkSize: Int = 4096) {
        precondition(chunkSize >= 1, "chunkSize must be at least 1, got \(chunkSize)")
        self.handle = handle
        self.chunkSize = chunkSize
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let reader = PCMChunkReader(handle: handle, chunkSamples: chunkSize)
        readers.replace(with: reader)
        return AsyncThrowingStream { try await reader.nextChunk() }
    }

    /// Ends the stream; a reader waiting for input notices within a few milliseconds.
    public func stop() {
        readers.stopCurrent()
    }
}
