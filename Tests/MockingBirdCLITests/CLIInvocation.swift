import Foundation
import MockingBirdCore
import MockingBirdTestSupport

/// Runs the built `mockingbird` binary and captures what it did.
///
/// stdin, stdout and stderr all go through temporary files, so large inputs or outputs
/// can never deadlock on a full pipe, and nothing blocks while the CLI runs.
struct CLIInvocation {
    let status: Int32
    let stdout: String
    let stderr: String

    /// Non-empty stdout lines.
    var lines: [String] { stdout.split(separator: "\n").map(String.init) }

    /// Every stdout line decoded as a `KeyResult`.
    func results() throws -> [KeyResult] {
        try lines.map { try JSONDecoder().decode(KeyResult.self, from: Data($0.utf8)) }
    }

    /// - Parameter stdin: bytes for stdin; `nil` connects `/dev/null`.
    static func run(_ arguments: [String], stdin: Data? = nil) async throws -> CLIInvocation {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("mockingbird-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let inURL = stdin.map { _ in scratch.appendingPathComponent("stdin") }
            ?? URL(fileURLWithPath: "/dev/null")
        if let stdin { try stdin.write(to: inURL) }
        let outURL = scratch.appendingPathComponent("stdout")
        let errURL = scratch.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)

        let process = Process()
        process.executableURL = try BuiltProducts.executable("mockingbird")
        process.arguments = arguments
        process.standardInput = try FileHandle(forReadingFrom: inURL)
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = try FileHandle(forWritingTo: errURL)
        // Await exit through terminationHandler: waitUntilExit() would block a thread of
        // the cooperative pool for the CLI's whole run, and on a 2-core CI runner a couple
        // of those starve every other async test.
        let (exited, exitContinuation) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exitContinuation.yield()
            exitContinuation.finish()
        }
        try process.run()
        for await _ in exited {}

        return CLIInvocation(
            status: process.terminationStatus,
            stdout: String(decoding: try Data(contentsOf: outURL), as: UTF8.self),
            stderr: String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
        )
    }
}
