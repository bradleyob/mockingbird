import Foundation
import Testing
@testable import MockingBirdServer

@Suite struct ServerOptionsParserTests {
    private let serverExecutable = URL(fileURLWithPath: "/opt/mb/bin/mockingbird-server")

    private func parse(_ arguments: [String]) throws -> ServerCommand {
        try ServerOptionsParser.parse(arguments, serverExecutable: serverExecutable)
    }

    private func options(_ arguments: [String]) throws -> ServerOptions {
        let command = try parse(arguments)
        guard case .run(let options) = command else {
            Issue.record("expected .run, got \(command)")
            throw CancellationError()
        }
        return options
    }

    @Test func defaultsMatchContract() throws {
        let parsed = try options([])
        #expect(parsed.host == "127.0.0.1")
        #expect(parsed.port == 7742)
        #expect(parsed.maxConnections == 4)
        #expect(parsed.maxBodyBytes == 104_857_600)
        #expect(parsed.mockingbird.path == "/opt/mb/bin/mockingbird")
    }

    @Test func everyFlagIsParsed() throws {
        let parsed = try options([
            "--port", "9000", "--host", "0.0.0.0", "--max-connections", "2",
            "--mockingbird", "/usr/local/bin/mockingbird", "--max-body-bytes", "1024",
        ])
        #expect(parsed.host == "0.0.0.0")
        #expect(parsed.port == 9000)
        #expect(parsed.maxConnections == 2)
        #expect(parsed.maxBodyBytes == 1024)
        #expect(parsed.mockingbird.path == "/usr/local/bin/mockingbird")
    }

    @Test func helpIsRecognised() throws {
        #expect(try parse(["--help"]) == .help)
    }

    @Test(arguments: [
        (["--binary", "/x"], "--binary"),
        (["--bogus"], "--bogus"),
        (["stray"], "stray"),
        (["--port"], "--port"),
        (["--port", "abc"], "--port"),
        (["--port", "70000"], "--port"),
        (["--max-connections", "0"], "--max-connections"),
        (["--max-connections", "-3"], "--max-connections"),
        (["--max-body-bytes", "0"], "--max-body-bytes"),
        (["--host", ""], "--host"),
        (["--mockingbird", ""], "--mockingbird"),
    ])
    func badArgumentsAreUsageErrors(arguments: [String], named flag: String) {
        #expect {
            try parse(arguments)
        } throws: { error in
            guard let usage = error as? ServerUsageError else { return false }
            return usage.message.contains(flag)
        }
    }
}
