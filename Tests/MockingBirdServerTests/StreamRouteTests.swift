import Foundation
import HummingbirdWSClient
import Logging
import MockingBirdTestSupport
import NIOCore
import NIOWebSocket
import Testing
@testable import MockingBirdServer

@Suite(.timeLimit(.minutes(1))) struct StreamRouteTests {
    private static let rawCadence = AudioFixture.rawFloat32(ToneSynth.majorCadence(root: 60))
    private static let frameSize = 16_384

    private struct Session: Sendable {
        var texts: [String] = []
        var firstFrameAt: ContinuousClock.Instant?
        var lastFrameAt: ContinuousClock.Instant?
        var closeCode: WebSocketErrorCode?
    }

    /// Runs `body` with a live server and its pool.
    private func withServer(
        cli: CLIUnderTest,
        maxConnections: Int = 4,
        _ body: @Sendable (_ port: Int, _ pool: ProcessPool) async throws -> Void
    ) async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let builder = ApplicationBuilder(options: .testing(
            mockingbird: try cli.executable(in: fake), maxConnections: maxConnections))
        try await LiveServer.run(builder) { port in
            try await body(port, builder.pool)
        }
    }

    /// Connects, sends `audio` in binary frames (optionally pausing first), optionally sends
    /// `end`, and collects every text frame until the server closes.
    private func stream(
        port: Int,
        query: String = "",
        audio: Data,
        upTo limit: Int? = nil,
        pauseBeforeEnd: Duration = .zero,
        sendEnd: Bool = true
    ) async throws -> Session {
        let collected = SessionBox()
        let closeFrame = try await WebSocketClient.connect(
            url: "ws://127.0.0.1:\(port)/stream\(query)",
            configuration: .init(maxFrameSize: 1 << 20),
            logger: Logger(label: "stream-test")
        ) { inbound, outbound, _ in
            // Read while writing, like a real client: an early error frame and close from the
            // server are answered at once instead of after all audio is sent.
            try await withThrowingTaskGroup(of: Void.self) { group in
                if sendEnd {
                    group.addTask {
                        for try await message in inbound.messages(maxSize: 1 << 20) {
                            if case .text(let text) = message {
                                await collected.append(text)
                            }
                        }
                    }
                }
                do {
                    let end = min(limit ?? audio.count, audio.count)
                    var offset = 0
                    while offset < end {
                        let next = min(offset + Self.frameSize, end)
                        try await outbound.write(.binary(ByteBuffer(bytes: audio[offset..<next])))
                        offset = next
                    }
                    if sendEnd {
                        try await Task.sleep(for: pauseBeforeEnd)
                        try await outbound.write(.text("end"))
                    }
                } catch {
                    // The server closed first (error frame); the reader collects what it sent.
                }
                try await group.waitForAll()
            }
        }
        var session = await collected.session
        session.closeCode = closeFrame?.closeCode
        return session
    }

    private actor SessionBox {
        var session = Session()
        func append(_ text: String) {
            let now = ContinuousClock.now
            session.texts.append(text)
            session.firstFrameAt = session.firstFrameAt ?? now
            session.lastFrameAt = now
        }
    }

    private func jsonObject(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func waitUntilIdle(_ pool: ProcessPool, within limit: Duration = .seconds(5)) async throws -> Int {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, await pool.activeCount > 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        return await pool.activeCount
    }

    @Test(arguments: CLIUnderTest.all)
    func cadenceStreamsAResultPerHopThenClosesNormally(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port, pool in
            let session = try await stream(port: port, audio: Self.rawCadence)
            #expect(session.texts.count >= 50)
            for text in session.texts {
                #expect(try jsonObject(text)["key"] != nil, "\(text)")
            }
            #expect(session.closeCode == .normalClosure)
            #expect(try await waitUntilIdle(pool) == 0)
        }
    }

    @Test(arguments: CLIUnderTest.all)
    func secondSocketWaitsForTheOnlySlot(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli, maxConnections: 1) { port, pool in
            let first = Task {
                try await stream(port: port, audio: Self.rawCadence, pauseBeforeEnd: .milliseconds(600))
            }
            let deadline = ContinuousClock.now + .seconds(10)
            while await pool.activeCount == 0 {
                try #require(ContinuousClock.now < deadline, "first socket never took a slot")
                try await Task.sleep(for: .milliseconds(10))
            }
            let second = Task { try await stream(port: port, audio: Self.rawCadence) }

            let firstSession = try await first.value
            let secondSession = try await second.value

            #expect(firstSession.texts.count >= 50)
            #expect(secondSession.texts.count >= 50)
            #expect(firstSession.closeCode == .normalClosure)
            #expect(secondSession.closeCode == .normalClosure)
            let firstDone = try #require(firstSession.lastFrameAt)
            let secondStarted = try #require(secondSession.firstFrameAt)
            #expect(secondStarted >= firstDone)
        }
    }

    @Test(arguments: CLIUnderTest.all)
    func disconnectMidStreamTerminatesTheSubprocess(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port, pool in
            _ = try await stream(port: port, audio: Self.rawCadence, upTo: Self.rawCadence.count / 2, sendEnd: false)
            #expect(try await waitUntilIdle(pool) == 0)
        }
    }

    @Test func badQueryParameterSendsErrorFrameAndCloses1011() async throws {
        try await withServer(cli: .contractFake) { port, pool in
            let outcome = try await RawWebSocketProbe.run(port: port, path: "/stream?windowSize=1000", sendText: "end")
            #expect(outcome.upgraded)
            #expect(outcome.texts.count == 1)
            let body = try JSONDecoder().decode(APIErrorBody.self, from: Data(try #require(outcome.texts.first).utf8))
            #expect(body.error.code == "invalid_parameter")
            #expect(outcome.closeCode == 1011)
            #expect(await pool.activeCount == 0)
        }
    }

    @Test(arguments: CLIUnderTest.contractConforming)
    func tooLittleAudioSendsInsufficientAudioAndCloses1011(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port, _ in
            let session = try await stream(port: port, audio: Self.rawCadence.prefix(400))
            let last = try #require(session.texts.last)
            let body = try JSONDecoder().decode(APIErrorBody.self, from: Data(last.utf8))
            #expect(body.error.code == "insufficient_audio")
            #expect(session.closeCode == .unexpectedServerError)
        }
    }

    @Test func unalignedFramesArePassedThroughByteForByte() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let counter = try fake.script("counter", #"printf '{"bytes":%s}\n' "$(wc -c | tr -d ' ')""#)
        let builder = ApplicationBuilder(options: .testing(mockingbird: counter))
        try await LiveServer.run(builder) { port in
            let session = try await stream(port: port, audio: Data(repeating: 1, count: 100_003))
            #expect(session.texts == [#"{"bytes":100003}"#])
        }
    }

    @Test func missingCLISendsSpawnFailed() async throws {
        let builder = ApplicationBuilder(options: .testing())
        try await LiveServer.run(builder) { port in
            let outcome = try await RawWebSocketProbe.run(port: port, path: "/stream", sendText: "end")
            #expect(outcome.upgraded)
            let body = try JSONDecoder().decode(APIErrorBody.self, from: Data(try #require(outcome.texts.last).utf8))
            #expect(body.error.code == "spawn_failed")
            #expect(outcome.closeCode == 1011)
            #expect(await builder.pool.activeCount == 0)
        }
    }
}
