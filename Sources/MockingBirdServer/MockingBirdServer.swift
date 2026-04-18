import Foundation
import Hummingbird

// MARK: - Entry point for the `mockingbird-server` HTTP/WebSocket gateway.
//
// Spawns `mockingbird` subprocesses — one per active connection.
// No DSP. No MockingBirdCore. Speaks only process I/O and HTTP/WebSocket.
//
// Usage: mockingbird-server [--host 0.0.0.0] [--port 8080] [--max-connections 4]
//                           [--binary /path/to/mockingbird]

@main
struct MockingBirdServer {
    static func main() async throws {
        let args = CommandLine.arguments
        let host = arg("--host", in: args) ?? "127.0.0.1"
        let port = Int(arg("--port", in: args) ?? "8080") ?? 8080
        let maxConnections = Int(arg("--max-connections", in: args) ?? "4") ?? 4
        let binaryPath = arg("--binary", in: args) ?? "mockingbird"

        let pool = ProcessPool(maxConnections: maxConnections, binaryPath: binaryPath)

        let router = Router()
        router.get("/health") { _, _ in "ok" }

        // TODO: MB-17 — wire ProcessPool into POST /analyze and WebSocket /stream
        _ = pool

        let app = Application(router: router, configuration: .init(address: .hostname(host, port: port)))
        try await app.runService()
    }

    private static func arg(_ flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
