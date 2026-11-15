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
    ///
    /// The script is written under a scratch name and copied into place by a `cp`
    /// subprocess, so this test process never holds a write descriptor on the file it will
    /// execute. Otherwise a child forked concurrently by another test can inherit that
    /// descriptor and make the exec fail with `ETXTBSY` (seen on Linux).
    func script(_ name: String, _ body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let source = directory.appendingPathComponent(".\(name).\(UUID().uuidString).src")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: source)
        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/bin/cp")
        copy.arguments = [source.path, url.path]
        try copy.run()
        copy.waitUntilExit()
        guard copy.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.removeItem(at: source)
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
