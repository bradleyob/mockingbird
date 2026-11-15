import Foundation

/// Process-wide signal setup for the server.
enum SignalDisposition {
    /// Ignores `SIGPIPE`. A `mockingbird` subprocess that exits early (bad input, usage
    /// error) closes its stdin; the next write must fail with `EPIPE`, not kill the server.
    /// Idempotent.
    static func ignoreBrokenPipe() {
        _ = signal(SIGPIPE, SIG_IGN)
    }
}
