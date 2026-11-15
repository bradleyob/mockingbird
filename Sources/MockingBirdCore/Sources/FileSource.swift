import Foundation

/// Reads PCM audio from a raw binary file (mono Float32 little-endian).
///
/// Intended for offline analysis (`.raw`, `.pcm`, `.f32` in the CLI) and testing.
/// The file is read in chunks as the stream is consumed, never loaded whole.
public struct FileSource: AudioSource {
    private let url: URL
    private let chunkSize: Int
    private let readers = ReaderRegistry()

    /// - Parameters:
    ///   - url: File of Float32 LE samples at the sample rate passed to `start`.
    ///   - chunkSize: Maximum samples per delivered chunk; at least 1.
    public init(url: URL, chunkSize: Int = 4096) {
        precondition(chunkSize >= 1, "chunkSize must be at least 1, got \(chunkSize)")
        self.url = url
        self.chunkSize = chunkSize
    }

    /// - Throws: `AudioSourceError.unknown` if the file cannot be opened.
    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw AudioSourceError.unknown("cannot open \(url.path): \(error.localizedDescription)")
        }
        let reader = PCMChunkReader(handle: handle, chunkSamples: chunkSize)
        readers.replace(with: reader)
        return AsyncThrowingStream { try reader.nextChunk() }
    }

    /// Ends the stream at the next chunk boundary.
    public func stop() {
        readers.stopCurrent()
    }
}
