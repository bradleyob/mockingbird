import MockingBirdCore

/// Wraps another `AudioSource` and finishes the stream after a fixed number of samples,
/// stopping the wrapped source. Implements `--duration`.
///
/// Counting samples (rather than watching result timestamps) makes the cut exact and
/// independent of how the pipeline timestamps results.
struct DurationLimitedSource: AudioSource {
    let base: any AudioSource
    let sampleLimit: Int

    init(base: any AudioSource, sampleLimit: Int) {
        precondition(sampleLimit > 0, "sampleLimit must be positive")
        self.base = base
        self.sampleLimit = sampleLimit
    }

    func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let upstream = try base.start(sampleRate: sampleRate)
        let base = base
        let limit = sampleLimit
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var delivered = 0
                    for try await chunk in upstream {
                        let take = min(chunk.count, limit - delivered)
                        continuation.yield(take == chunk.count ? chunk : Array(chunk.prefix(take)))
                        delivered += take
                        if delivered >= limit { break }
                    }
                    base.stop()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() {
        base.stop()
    }
}
