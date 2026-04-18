import Foundation

/// Reads raw PCM samples from a `FileHandle` (stdin or any file descriptor).
///
/// Reads `Float32` samples in chunks. Use this to pipe PCM data into the
/// `mockingbird` CLI via stdin: `ffmpeg -i song.mp3 -f f32le -ar 44100 -ac 1 - | mockingbird`
public struct RawPCMSource: AudioSource {
    private let handle: FileHandle
    /// Number of Float32 samples to read per chunk.
    private let chunkSize: Int

    public init(handle: FileHandle = .standardInput, chunkSize: Int = 4096) {
        self.handle = handle
        self.chunkSize = chunkSize
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let fileHandle = handle
        let size = chunkSize
        return AsyncThrowingStream { continuation in
            Task {
                let byteCount = size * MemoryLayout<Float>.size
                while true {
                    let data = fileHandle.readData(ofLength: byteCount)
                    guard !data.isEmpty else {
                        continuation.finish()
                        return
                    }
                    let count = data.count / MemoryLayout<Float>.size
                    var samples = [Float](repeating: 0, count: count)
                    _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
                    continuation.yield(samples)
                }
            }
        }
    }

    public func stop() {
        // Closing stdin is destructive; stopping is handled by the caller
        // terminating the process or closing the write end of the pipe.
    }
}
