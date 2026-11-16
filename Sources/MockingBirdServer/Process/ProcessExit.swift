/// How a `mockingbird` subprocess ended.
struct ProcessExit: Equatable, Sendable {
    /// Exit status, or the signal number when `signalled` is true.
    let status: Int32
    /// The process was killed by a signal rather than exiting.
    let signalled: Bool
    /// Everything the process wrote to stderr.
    let standardError: String

    var isSuccess: Bool { !signalled && status == 0 }
}
