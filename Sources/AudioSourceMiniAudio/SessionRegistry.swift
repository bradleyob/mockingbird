import Foundation

/// Something a source has started and must be able to stop from `stop()`.
protocol ClosableSession: AnyObject, Sendable {
    func close()
}

/// The sessions a source has started, so `stop()` (synchronous, callable from any thread)
/// can close them. The lock guards only this list; it is never touched by the audio callback.
final class SessionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [any ClosableSession] = []

    func add(_ session: any ClosableSession) {
        lock.withLock {
            sessions.removeAll { $0 === session }
            sessions.append(session)
        }
    }

    /// Closes and forgets every registered session.
    func closeAll() {
        let closing = lock.withLock {
            let current = sessions
            sessions = []
            return current
        }
        closing.forEach { $0.close() }
    }
}
