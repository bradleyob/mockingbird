import Foundation

/// Maps how the CLI ended to the server's error vocabulary (contracts §4.3 → §4.4).
enum ProcessExitClassifier {
    /// Longest stderr excerpt copied into an error message.
    static let maxMessageLength = 2000

    /// `nil` when the CLI succeeded; otherwise the error to report.
    static func error(for exit: ProcessExit) -> APIError? {
        if exit.isSuccess {
            return nil
        }
        if exit.signalled {
            return .analysisFailed(message(exit, fallback: "mockingbird was killed by signal \(exit.status)"))
        }
        switch exit.status {
        case 3:
            return .insufficientAudio(message(exit, fallback: "input ended before one full analysis window"))
        case 4:
            return .undecodableAudio(message(exit, fallback: "audio could not be read or decoded"))
        default:
            return .analysisFailed(message(exit, fallback: "mockingbird exited with status \(exit.status)"))
        }
    }

    /// The single KeyResult line for `POST /analyze`, or the error to report instead.
    static func keyResultLine(exit: ProcessExit, lastLine: String?) throws(APIError) -> String {
        if let error = error(for: exit) {
            throw error
        }
        guard let lastLine else {
            throw APIError.analysisFailed("mockingbird exited without producing a result")
        }
        return lastLine
    }

    private static func message(_ exit: ProcessExit, fallback: String) -> String {
        let text = exit.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallback }
        return String(text.prefix(maxMessageLength))
    }
}
