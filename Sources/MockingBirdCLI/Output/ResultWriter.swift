import Foundation

/// Writes result lines to stdout (or any handle), one `write` per line.
///
/// `FileHandle` writes go straight to the file descriptor with no user-space buffer,
/// so each line is visible to a reading process (the server) as soon as it is written.
struct ResultWriter: Sendable {
    let handle: FileHandle

    init(handle: FileHandle = .standardOutput) {
        self.handle = handle
    }

    /// Writes `line` followed by a newline.
    ///
    /// - Throws: the underlying write error (for example, the reader closed the pipe).
    func write(line: String) throws {
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
