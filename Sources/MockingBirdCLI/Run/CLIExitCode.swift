/// `mockingbird` process exit statuses (part of the CLI contract the server relies on).
enum CLIExitCode: Int32, Sendable {
    /// Success.
    case ok = 0
    /// Audio source or pipeline failure at runtime.
    case runtimeFailure = 1
    /// Unknown flag or bad flag value.
    case usage = 2
    /// Input ended before one full analysis window, so there is no result.
    case insufficientAudio = 3
    /// Input file missing or undecodable, or `--profiles` file invalid.
    case unreadableInput = 4
}
