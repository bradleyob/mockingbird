import Foundation
import MockingBirdTestSupport
import Testing

/// Which `mockingbird` binary a server test runs against.
enum CLIUnderTest: String, CustomTestStringConvertible, Sendable {
    /// `ContractFakeCLI`, written to a temp dir. Always available.
    case contractFake
    /// The real `mockingbird` built by this package.
    case real

    var testDescription: String { rawValue }

    /// The real CLI, plus the fake. The real one is always runnable, but before the CLI
    /// branch merges it predates contract §4.3, so only use this list for behaviour the old
    /// CLI also has (raw PCM on stdin → JSON lines, exit 0).
    static let all: [CLIUnderTest] = [.contractFake, .real]

    /// Variants that implement contract §4.3 (exit codes 3/4, positional files, one line).
    /// The real CLI joins automatically once it does: detected by `--version` printing.
    static let contractConforming: [CLIUnderTest] = realCLIFollowsContract ? [.contractFake, .real] : [.contractFake]

    /// URL of the binary, writing the fake into `fake` when needed.
    func executable(in fake: FakeExecutable) throws -> URL {
        switch self {
        case .contractFake:
            return try fake.script("mockingbird", ContractFakeCLI.script)
        case .real:
            return try BuiltProducts.executable("mockingbird")
        }
    }

    private static let realCLIFollowsContract: Bool = {
        guard let url = try? BuiltProducts.executable("mockingbird") else { return false }
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty
    }()
}
