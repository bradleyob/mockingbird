import Foundation
import Hummingbird
import HummingbirdWebSocket

/// Builds the `mockingbird-server` Hummingbird application for a set of options, so that
/// `main` and the tests run exactly the same routes.
struct ApplicationBuilder: Sendable {
    let options: ServerOptions

    init(options: ServerOptions) {
        self.options = options
    }

    func build() -> some ApplicationProtocol {
        SignalDisposition.ignoreBrokenPipe()
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.get("/health") { _, _ in "ok" }
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
