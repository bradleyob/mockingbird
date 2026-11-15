import Foundation
import Hummingbird
import MockingBirdTestSupport
import Testing
@testable import MockingBirdServer

@Suite struct AnalyzeRouteTests {
    private static let cadence = ToneSynth.majorCadence(root: 60)
    private static let rawCadence = AudioFixture.rawFloat32(cadence)
    private static let wavCadence = AudioFixture.wav16(cadence)

    /// Runs `body` against a live server on an ephemeral loopback port.
    private func withServer(
        cli: CLIUnderTest,
        maxConnections: Int = 4,
        maxBodyBytes: Int = ServerOptions.defaultMaxBodyBytes,
        _ body: @Sendable (_ port: Int) async throws -> Void
    ) async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let uploads = fake.path("uploads")
        try FileManager.default.createDirectory(at: uploads, withIntermediateDirectories: true)
        let options = ServerOptions.testing(
            mockingbird: try cli.executable(in: fake),
            maxConnections: maxConnections,
            maxBodyBytes: maxBodyBytes,
            temporaryDirectory: uploads
        )
        try await LiveServer.run(ApplicationBuilder(options: options)) { port in
            try await body(port)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: uploads.path)
        #expect(leftovers.isEmpty, "temp files left behind: \(leftovers)")
    }

    private func post(
        _ port: Int,
        query: String = "",
        contentType: String? = "application/octet-stream",
        body: Data
    ) async throws -> LiveServer.HTTPResult {
        var headers: HTTPFields = [:]
        if let contentType {
            headers[.contentType] = contentType
        }
        return try await LiveServer.request(port: port, "/analyze" + query, method: .post, headers: headers, body: body)
    }

    private func errorCode(_ response: LiveServer.HTTPResult) throws -> String {
        try JSONDecoder().decode(APIErrorBody.self, from: Data(response.body.readableBytesView)).error.code
    }

    private func keyResultObject(_ response: LiveServer.HTTPResult) throws -> [String: Any] {
        let text = String(buffer: response.body).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!text.contains("\n"), "expected exactly one line")
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    // MARK: - Success

    @Test(arguments: CLIUnderTest.all)
    func rawCadenceReturnsOneKeyResult(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port in
            for contentType in ["application/octet-stream", "audio/pcm", nil] {
                let response = try await post(port, contentType: contentType, body: Self.rawCadence)
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json")
                #expect(try keyResultObject(response)["key"] != nil)
            }
        }
    }

    @Test(arguments: CLIUnderTest.contractConforming)
    func wavBodyReturnsOneKeyResult(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port in
            for contentType in ["audio/wav", "audio/x-wav", "audio/wave"] {
                let response = try await post(port, contentType: contentType, body: Self.wavCadence)
                #expect(response.status == .ok, "\(contentType): \(String(buffer: response.body))")
                #expect(try keyResultObject(response)["key"] != nil)
            }
        }
    }

    @Test func queryParametersReachTheCLIAsArgv() async throws {
        try await withServer(cli: .contractFake) { port in
            let response = try await post(
                port,
                query: "?sampleRate=48000&windowSize=8192&hopSize=1024&alternates=1&zeroPad=true",
                body: Self.rawCadence)
            #expect(response.status == .ok)
            let argv = try #require(try keyResultObject(response)["argv"] as? String)
            #expect(argv.contains("--sample-rate 48000"))
            #expect(argv.contains("--window-size 8192"))
            #expect(argv.contains("--hop-size 1024"))
            #expect(argv.contains("--alternates 1"))
            #expect(argv.contains("--zero-pad"))
        }
    }

    @Test(arguments: CLIUnderTest.all)
    func sixConcurrentRequestsWithTwoSlotsAllSucceed(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli, maxConnections: 2) { port in
            let statuses = try await withThrowingTaskGroup(of: HTTPResponse.Status.self) { group in
                for _ in 0..<6 {
                    group.addTask { try await post(port, body: Self.rawCadence).status }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
            #expect(statuses == Array(repeating: .ok, count: 6))
        }
    }

    // MARK: - Client errors

    @Test func emptyBodyIs400() async throws {
        try await withServer(cli: .contractFake) { port in
            let response = try await post(port, body: Data())
            #expect(response.status == .badRequest)
            #expect(try errorCode(response) == "empty_body")
        }
    }

    @Test(arguments: [
        "?windowSize=1000", "?windowSize=abc", "?sampleRate=0", "?sampleRate=-1",
        "?hopSize=0", "?hopSize=8192", "?windowSize=1024&hopSize=2048", "?alternates=-1",
        "?zeroPad=maybe", "?sampleRate=44100;rm",
    ])
    func invalidParameterIs400(query: String) async throws {
        try await withServer(cli: .contractFake) { port in
            let response = try await post(port, query: query, body: Self.rawCadence)
            #expect(response.status == .badRequest)
            #expect(try errorCode(response) == "invalid_parameter")
        }
    }

    @Test(arguments: ["text/plain", "application/json", "video/mp4"])
    func unsupportedMediaTypeIs415(contentType: String) async throws {
        try await withServer(cli: .contractFake) { port in
            let response = try await post(port, contentType: contentType, body: Data("x".utf8))
            #expect(response.status == .unsupportedMediaType)
            #expect(try errorCode(response) == "unsupported_media_type")
        }
    }

    @Test func bodyOverLimitIs413() async throws {
        try await withServer(cli: .contractFake, maxBodyBytes: 1000) { port in
            let response = try await post(port, body: Data(count: 1001))
            #expect(response.status == .contentTooLarge)
            #expect(try errorCode(response) == "payload_too_large")
            let atLimit = try await post(port, body: Data(count: 1000))
            #expect(atLimit.status != .contentTooLarge)
        }
    }

    // MARK: - CLI failures

    @Test(arguments: CLIUnderTest.contractConforming)
    func tooLittleRawAudioIs422(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port in
            let response = try await post(port, body: AudioFixture.rawFloat32(Array(Self.cadence.prefix(100))))
            #expect(response.status == .unprocessableContent)
            #expect(try errorCode(response) == "insufficient_audio")
        }
    }

    @Test(arguments: CLIUnderTest.contractConforming)
    func garbageWavIs422(cli: CLIUnderTest) async throws {
        try await withServer(cli: cli) { port in
            let response = try await post(port, contentType: "audio/wav", body: Data(repeating: 0x41, count: 5000))
            #expect(response.status == .unprocessableContent)
            #expect(try errorCode(response) == "undecodable_audio")
        }
    }

    @Test func otherCLIFailureIs500WithStderr() async throws {
        let fake = try FakeExecutable()
        defer { fake.remove() }
        let broken = try fake.script("broken", "cat > /dev/null; echo 'mockingbird: error: boom' >&2; exit 1")
        try await LiveServer.run(ApplicationBuilder(options: .testing(mockingbird: broken))) { port in
            let response = try await post(port, body: Self.rawCadence)
            #expect(response.status == .internalServerError)
            let body = try JSONDecoder().decode(APIErrorBody.self, from: Data(response.body.readableBytesView))
            #expect(body.error.code == "analysis_failed")
            #expect(body.error.message.contains("boom"))
        }
    }

    @Test func missingCLIIs500SpawnFailed() async throws {
        try await LiveServer.run(ApplicationBuilder(options: .testing())) { port in
            let response = try await post(port, body: Self.rawCadence)
            #expect(response.status == .internalServerError)
            #expect(try errorCode(response) == "spawn_failed")
        }
    }
}
