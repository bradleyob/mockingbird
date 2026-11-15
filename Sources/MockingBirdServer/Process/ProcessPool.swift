import Foundation

/// Bounds the number of live `mockingbird` subprocesses, like a connection pool.
///
/// - At most `maxConnections` subprocesses are alive at once.
/// - Further jobs wait in FIFO order; they are never rejected.
/// - Every job gets a fresh process; nothing is reused.
/// - A slot is held for the whole life of its subprocess and released only after the
///   process has exited — on success, on error, and on cancellation.
actor ProcessPool {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    let maxConnections: Int
    /// Slots currently held (each by a live or exiting subprocess, or one about to spawn).
    private(set) var activeCount = 0
    private var waiters: [Waiter] = []
    private var nextWaiterID: UInt64 = 0

    /// Jobs queued for a slot.
    var waitingCount: Int { waiters.count }

    init(maxConnections: Int) {
        precondition(maxConnections > 0, "maxConnections must be positive")
        self.maxConnections = maxConnections
    }

    /// Waits for a slot, spawns `executable`, runs `body` with the process, and releases the
    /// slot once the process has exited. If `body` returns or throws while the process is
    /// still running, the process is terminated first.
    ///
    /// - Throws: `CancellationError` if cancelled while queued, `APIError.spawnFailed`, or
    ///   whatever `body` throws.
    nonisolated func run<T: Sendable>(
        executable: URL,
        arguments: [String],
        standardInput: StandardInputMode,
        _ body: @Sendable (MockingbirdProcess) async throws -> T
    ) async throws -> T {
        try await acquire()
        let process: MockingbirdProcess
        do {
            process = try MockingbirdProcess.launch(
                executable: executable, arguments: arguments, standardInput: standardInput)
        } catch {
            await release()
            throw error
        }
        let result: Result<T, any Error>
        do {
            result = .success(try await body(process))
        } catch {
            result = .failure(error)
        }
        process.terminate()
        _ = await process.exit()
        await release()
        return try result.get()
    }

    private func acquire() async throws {
        if activeCount < maxConnections && waiters.isEmpty {
            activeCount += 1
            return
        }
        let id = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Hands the slot straight to the oldest waiter, or frees it.
    private func release() {
        if waiters.isEmpty {
            activeCount -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
