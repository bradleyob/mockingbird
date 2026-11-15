import Foundation
import Testing
@testable import MockingBirdServer

@Suite struct ProcessPoolTests {
    /// A job that logs its start and end, holds its slot for 0.3 s, drains stdin and prints
    /// one JSON line.
    private func loggingJob(in fake: FakeExecutable) throws -> (script: URL, log: URL) {
        let log = fake.path("jobs.log")
        let script = try fake.script("job", """
            echo "start $$" >> '\(log.path)'
            sleep 0.3
            cat > /dev/null
            echo "end $$" >> '\(log.path)'
            echo '{"key":"C"}'
            """)
        return (script, log)
    }

    /// Largest number of jobs that were between their `start` and `end` log lines at once.
    private func maxOverlap(in log: URL) throws -> Int {
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        var running = 0
        var peak = 0
        for line in lines {
            running += line.hasPrefix("start") ? 1 : -1
            peak = max(peak, running)
        }
        return peak
    }

    private func runJobs(_ count: Int, pool: ProcessPool, executable: URL) async throws -> [(ProcessExit, [String])] {
        try await withThrowingTaskGroup(of: (ProcessExit, [String]).self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await pool.run(executable: executable, arguments: [], standardInput: .pipe) { process in
                        try process.closeStandardInput()
                        var lines: [String] = []
                        for await line in process.standardOutputLines {
                            lines.append(line)
                        }
                        return (await process.exit(), lines)
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
    }

    @Test func oneSlotSerialisesJobs() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let job = try loggingJob(in: fake)
        let pool = ProcessPool(maxConnections: 1)

        let results = try await runJobs(4, pool: pool, executable: job.script)

        #expect(results.count == 4)
        for (exit, lines) in results {
            #expect(exit.isSuccess)
            #expect(lines == [#"{"key":"C"}"#])
        }
        #expect(try maxOverlap(in: job.log) == 1)
        #expect(await pool.activeCount == 0)
    }

    @Test func twoSlotsAllowAtMostTwoAtOnce() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let job = try loggingJob(in: fake)
        let pool = ProcessPool(maxConnections: 2)

        let results = try await runJobs(4, pool: pool, executable: job.script)

        #expect(results.allSatisfy { $0.0.isSuccess })
        #expect(try maxOverlap(in: job.log) <= 2)
        #expect(await pool.activeCount == 0)
    }

    @Test func spawnFailureReleasesTheSlot() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let job = try loggingJob(in: fake)
        let pool = ProcessPool(maxConnections: 1)

        await #expect {
            try await pool.run(executable: fake.path("missing"), arguments: [], standardInput: .pipe) { _ in 0 }
        } throws: { error in
            (error as? APIError)?.code == "spawn_failed"
        }

        let results = try await runJobs(1, pool: pool, executable: job.script)
        #expect(results.first?.0.isSuccess == true)
        #expect(await pool.activeCount == 0)
    }

    @Test func cancelledWaiterNeverTakesASlot() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let job = try loggingJob(in: fake)
        let pool = ProcessPool(maxConnections: 1)

        let holder = Task { try await runJobs(1, pool: pool, executable: job.script) }
        while await pool.activeCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let waiter = Task { try await runJobs(1, pool: pool, executable: job.script) }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()

        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(try await holder.value.count == 1)
        #expect(await pool.activeCount == 0)
        #expect(await pool.waitingCount == 0)
        #expect(try maxOverlap(in: job.log) == 1)
    }

    @Test func bodyThatThrowsStillReapsTheProcess() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let sleeper = try fake.script("sleeper", "sleep 30")
        let pool = ProcessPool(maxConnections: 1)
        struct Boom: Error {}

        let started = ContinuousClock.now
        await #expect(throws: Boom.self) {
            try await pool.run(executable: sleeper, arguments: [], standardInput: .pipe) { _ in
                throw Boom()
            }
        }
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(await pool.activeCount == 0)
    }
}
