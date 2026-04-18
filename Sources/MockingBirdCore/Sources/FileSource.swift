import Foundation

/// Reads PCM audio from a raw binary file (32-bit float, single channel).
///
/// Intended for offline analysis and testing. The file must contain
/// interleaved `Float32` samples at the caller-specified sample rate.
public struct FileSource: AudioSource {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let fileURL = url
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let count = data.count / MemoryLayout<Float>.size
                    var samples = [Float](repeating: 0, count: count)
                    _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
                    // Deliver in 4096-sample chunks matching typical window size
                    let chunkSize = 4096
                    var offset = 0
                    while offset < samples.count {
                        let end = min(offset + chunkSize, samples.count)
                        continuation.yield(Array(samples[offset..<end]))
                        offset = end
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AudioSourceError.unknown(error.localizedDescription))
                }
            }
        }
    }

    public func stop() {
        // File reading is not interruptible in this stub implementation.
        // A production implementation would cancel the Task.
    }
}
