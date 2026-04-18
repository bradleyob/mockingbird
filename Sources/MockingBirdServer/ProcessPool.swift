import Foundation

/// Manages a bounded pool of `mockingbird` subprocesses.
///
/// Behaves like a SQL connection pool:
/// - `maxConnections` processes may run concurrently.
/// - Additional requests queue (never rejected) until a slot is free.
/// - Each connection gets a fresh process; no reuse across connections.
actor ProcessPool {
    private let maxConnections: Int
    private let binaryPath: String
    private var activeCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConnections: Int, binaryPath: String) {
        precondition(maxConnections > 0, "maxConnections must be positive")
        self.maxConnections = maxConnections
        self.binaryPath = binaryPath
    }

    /// Acquires a slot, spawns a fresh `mockingbird` process, and calls `work`.
    /// Releases the slot when `work` returns or throws.
    func withProcess<T: Sendable>(
        _ work: (Process) async throws -> T
    ) async rethrows -> T {
        await acquireSlot()
        defer { releaseSlot() }
        let process = makeProcess()
        return try await work(process)
    }

    // MARK: - Private

    private func acquireSlot() async {
        if activeCount < maxConnections {
            activeCount += 1
        } else {
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
            activeCount += 1
        }
    }

    private func releaseSlot() {
        activeCount -= 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    private func makeProcess() -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }
}
