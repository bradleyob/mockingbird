import Foundation
import Hummingbird
import HummingbirdWebSocket

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

    func build() -> some ApplicationProtocol {
        SignalDisposition.ignoreBrokenPipe()
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.get("/health") { _, _ in "ok" }
        let analyze = AnalyzeHandler(options: options, pool: pool)
        router.post("/analyze") { request, _ in await analyze.handle(request) }
        return Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(
                address: .hostname(options.host, port: options.port),
                serverName: "mockingbird-server"
            )
        )
    }
}
