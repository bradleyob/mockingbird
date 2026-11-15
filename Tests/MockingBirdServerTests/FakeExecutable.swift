import Foundation

/// Writes small POSIX shell scripts to a private temp directory so server tests can spawn
/// stand-ins for the `mockingbird` CLI. Removes the directory on `remove()`.
struct FakeExecutable {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mockingbird-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes `body` (without the shebang) as an executable script named `name`.
    func script(_ name: String, _ body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// A file path inside the private directory (not created).
    func path(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            // Best effort: a leftover temp directory does not invalidate a test.
        }
    }
}
