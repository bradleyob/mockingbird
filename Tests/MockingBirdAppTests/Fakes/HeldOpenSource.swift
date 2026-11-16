import MockingBirdCore
import os

/// A live-source stand-in: delivers its samples, then keeps the stream open (like a
/// microphone) until `stop()` is called. Records whether `stop()` was called.
final class HeldOpenSource: AudioSource {
    private let samples: [Float]
    private let chunkSize: Int
    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var continuation: AsyncThrowingStream<[Float], Error>.Continuation?
        var stopCount = 0
    }

    init(samples: [Float], chunkSize: Int = 4096) {
        self.samples = samples
        self.chunkSize = chunkSize
    }

    var stopCount: Int { state.withLock { $0.stopCount } }

    func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let (stream, continuation) = AsyncThrowingStream<[Float], Error>.makeStream()
        state.withLockUnchecked { $0.continuation = continuation }
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            continuation.yield(Array(samples[offset..<end]))
            offset = end
        }
        return stream
    }

    func stop() {
        let continuation = state.withLockUnchecked { current -> AsyncThrowingStream<[Float], Error>.Continuation? in
            current.stopCount += 1
            defer { current.continuation = nil }
            return current.continuation
        }
        continuation?.finish()
    }
}
