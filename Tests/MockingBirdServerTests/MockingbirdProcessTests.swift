import Foundation
import Testing
@testable import MockingBirdServer

@Suite struct MockingbirdProcessTests {
    @Test func collectsStdoutLinesStderrAndStatus() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let script = try fake.script("talker", """
            printf 'one\\ntwo\\nthr'
            printf 'ee\\n'
            echo "args: $*" >&2
            exit 3
            """)

        let process = try MockingbirdProcess.launch(
            executable: script, arguments: ["--a", "b c"], standardInput: .none)
        var lines: [String] = []
        for await line in process.standardOutputLines {
            lines.append(line)
        }
        let exit = await process.exit()

        #expect(lines == ["one", "two", "three"])
        #expect(exit.status == 3)
        #expect(!exit.isSuccess)
        #expect(exit.standardError == "args: --a b c\n")
    }

    @Test func pipesStandardInput() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let script = try fake.script("counter", "wc -c | tr -d ' '")

        let process = try MockingbirdProcess.launch(executable: script, arguments: [], standardInput: .pipe)
        try process.write(Data(repeating: 7, count: 200_000))
        try process.closeStandardInput()
        var lines: [String] = []
        for await line in process.standardOutputLines {
            lines.append(line)
        }

        #expect(lines == ["200000"])
        #expect(await process.exit().isSuccess)
    }

    @Test func writingToAnExitedProcessThrowsInsteadOfKillingUs() async throws {
        SignalDisposition.ignoreBrokenPipe()
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let script = try fake.script("quitter", "exit 2")

        let process = try MockingbirdProcess.launch(executable: script, arguments: [], standardInput: .pipe)
        _ = await process.exit()
        #expect(throws: (any Error).self) {
            for _ in 0..<64 {
                try process.write(Data(repeating: 0, count: 65_536))
            }
        }
    }

    @Test func terminateStopsALongRunningProcess() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let script = try fake.script("sleeper", "exec sleep 30")

        let process = try MockingbirdProcess.launch(executable: script, arguments: [], standardInput: .pipe)
        process.terminate()
        let exit = await process.exit()

        #expect(!exit.isSuccess)
    }
}
