/// Why a `mockingbird` run failed, carrying the message for stderr.
enum CLIFailure: Error, Equatable, Codable, Sendable {
    /// The command line was invalid.
    case usage(CLIUsageError)
    /// The audio source or pipeline failed while running.
    case runtime(String)
    /// The input ended before one full analysis window.
    case insufficientAudio
    /// An input file or the profiles file could not be read or decoded.
    case unreadableInput(String)

    /// Process exit status for this failure.
    var exitCode: CLIExitCode {
        switch self {
        case .usage: .usage
        case .runtime: .runtimeFailure
        case .insufficientAudio: .insufficientAudio
        case .unreadableInput: .unreadableInput
        }
    }

    /// One-line explanation for stderr.
    var message: String {
        switch self {
        case .usage(let error): error.message
        case .runtime(let message): message
        case .insufficientAudio: "input ended before one full analysis window; no result"
        case .unreadableInput(let message): message
        }
    }
}
