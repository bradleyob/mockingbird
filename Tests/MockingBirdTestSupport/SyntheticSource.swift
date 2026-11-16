import MockingBirdCore

/// An `AudioSource` that delivers a pre-computed sample buffer in fixed-size chunks,
/// then finishes. Deterministic; no hardware required.
public struct SyntheticSource: AudioSource {
    public let samples: [Float]
    public let chunkSize: Int

    public init(samples: [Float], chunkSize: Int = 4096) {
        self.samples = samples
        self.chunkSize = max(chunkSize, 1)
    }

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let allSamples = samples
        let size = chunkSize
        return AsyncThrowingStream { continuation in
            var offset = 0
            while offset < allSamples.count {
                let end = min(offset + size, allSamples.count)
                continuation.yield(Array(allSamples[offset..<end]))
                offset = end
            }
            continuation.finish()
        }
    }

    public func stop() {}
}
