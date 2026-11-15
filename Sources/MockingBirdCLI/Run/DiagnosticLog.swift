import Foundation

/// Writes diagnostics to stderr. stdout carries results only.
struct DiagnosticLog: Sendable {
    let handle: FileHandle

    init(handle: FileHandle = .standardError) {
        self.handle = handle
    }

    /// Writes `mockingbird: error: <message>`.
    func error(_ message: String) {
        // A failed stderr write has nowhere left to be reported; the exit code still is.
        try? handle.write(contentsOf: Data("mockingbird: error: \(message)\n".utf8))
    }
}
