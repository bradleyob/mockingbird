import Foundation
import Hummingbird
import HummingbirdWebSocket
import NIOCore

/// Builds the `mockingbird-server` Hummingbird application for a set of options, so that
/// `main` and the tests run exactly the same routes.
struct ApplicationBuilder: Sendable {
    let options: ServerOptions
    /// Shared by every route, so `maxConnections` bounds HTTP and WebSocket work together.
    let pool: ProcessPool

    init(options: ServerOptions) {
        self.options = options
        self.pool = ProcessPool(maxConnections: options.maxConnections)
    }

    /// - Parameter onServerRunning: Called once the listening socket is bound (tests read the
    ///   ephemeral port from it).
    func build(
        onServerRunning: @escaping @Sendable (any Channel) async -> Void = { _ in }
    ) -> some ApplicationProtocol {
        SignalDisposition.ignoreBrokenPipe()
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.get("/health") { _, _ in "ok" }
        let analyze = AnalyzeHandler(options: options, pool: pool)
        router.post("/analyze") { request, _ in await analyze.handle(request) }
        let stream = StreamHandler(options: options, pool: pool)
        router.ws("/stream") { inbound, outbound, context in
            try await stream.handle(inbound: inbound, outbound: outbound, request: context.request)
        }
        return Application(
            router: router,
            server: .http1WebSocketUpgrade(
                webSocketRouter: router,
                configuration: .init(maxFrameSize: StreamHandler.maxMessageSize)
            ),
            configuration: .init(
                address: .hostname(options.host, port: options.port),
                serverName: "mockingbird-server"
            ),
            onServerRunning: onServerRunning
        )
    }
}
