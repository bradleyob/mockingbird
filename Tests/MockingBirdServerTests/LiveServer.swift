import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
@testable import MockingBirdServer

/// Runs a real `mockingbird-server` application on 127.0.0.1 with an ephemeral port.
///
/// Used instead of HummingbirdTesting's `.live` mode, which binds `localhost` (IPv6 here) and
/// sends every request over one keep-alive connection, so it could not show pool queueing.
enum LiveServer {
    struct HTTPResult: Sendable {
        let status: HTTPResponse.Status
        let headers: HTTPFields
        let body: ByteBuffer
    }

    static func run<T: Sendable>(
        _ builder: ApplicationBuilder,
        _ body: @Sendable (_ port: Int) async throws -> T
    ) async throws -> T {
        let (ports, portContinuation) = AsyncStream<Int>.makeStream()
        let app = builder.build { channel in
            portContinuation.yield(channel.localAddress?.port ?? 0)
            portContinuation.finish()
        }
        let server = Task {
            defer { portContinuation.finish() }
            try await app.runService(gracefulShutdownSignals: [])
        }
        var iterator = ports.makeAsyncIterator()
        guard let port = await iterator.next(), port > 0 else {
            server.cancel()
            try await server.value
            throw CancellationError()
        }
        let result: Result<T, any Error>
        do {
            result = .success(try await body(port))
        } catch {
            result = .failure(error)
        }
        server.cancel()
        _ = await server.result
        return try result.get()
    }

    /// One request on its own connection, so concurrent calls are concurrent on the server.
    static func request(
        port: Int,
        _ uri: String,
        method: HTTPRequest.Method = .get,
        headers: HTTPFields = [:],
        body: Data? = nil
    ) async throws -> HTTPResult {
        let client = TestClient(host: "127.0.0.1", port: port, configuration: .init(timeout: .seconds(60)))
        client.connect()
        let response: TestClient.Response
        do {
            response = try await client.execute(.init(
                uri, method: method, authority: "127.0.0.1", headers: headers,
                body: body.map { ByteBuffer(bytes: $0) }))
        } catch {
            try await client.shutdown()
            throw error
        }
        try await client.shutdown()
        return HTTPResult(status: response.head.status, headers: response.head.headerFields, body: response.body ?? ByteBuffer())
    }
}
