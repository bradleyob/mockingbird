/// The command line could not be understood: unknown flag, missing or bad value.
///
/// `mockingbird` reports it on stderr and exits with `CLIExitCode.usage`.
struct CLIUsageError: Error, Equatable, Codable, Sendable, CustomStringConvertible {
    /// Human-readable explanation naming the offending flag or argument.
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
