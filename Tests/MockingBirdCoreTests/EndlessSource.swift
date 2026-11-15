import Foundation
import MockingBirdCore

/// A test `AudioSource` that produces a tone forever until stopped or until its consumer
/// goes away, recording which of the two happened.
final class EndlessSource: AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<[Float], Error>.Continuation?
    private var stopCalls = 0
    private var terminations = 0

    var stopCount: Int { lock.withLock { stopCalls } }
    var terminationCount: Int { lock.withLock { terminations } }

    func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let (stream, continuation) = AsyncThrowingStream<[Float], Error>.makeStream()
        let chunk = (0..<1024).map { Float(sin(2 * Double.pi * 440 * Double($0) / sampleRate)) }
        let producer = Task {
            while !Task.isCancelled {
                continuation.yield(chunk)
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        continuation.onTermination = { [weak self] _ in
            producer.cancel()
            self?.lock.withLock { self?.terminations += 1 }
        }
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func stop() {
        let pending = lock.withLock { () -> AsyncThrowingStream<[Float], Error>.Continuation? in
            stopCalls += 1
            return continuation
        }
        pending?.finish()
    }
}
