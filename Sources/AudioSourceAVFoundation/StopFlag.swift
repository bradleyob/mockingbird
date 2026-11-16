import os

/// A thread-safe "stop requested" flag shared between a source's `stop()` and the task
/// that produces its stream.
final class StopFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    /// Whether `raise()` has been called since the last `reset()`.
    var isRaised: Bool { state.withLock { $0 } }

    func raise() { state.withLock { $0 = true } }

    func reset() { state.withLock { $0 = false } }
}
