import MockingBirdCore

/// Delivers some audio, then fails the stream with `error`.
struct FailingSource: AudioSource {
    let samples: [Float]
    let error: AudioSourceError

    func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let samples = samples
        let error = error
        return AsyncThrowingStream { continuation in
            continuation.yield(samples)
            continuation.finish(throwing: error)
        }
    }

    func stop() {}
}
