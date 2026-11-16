import Foundation

/// Runtime configuration of `mockingbird-server` (contract §4.4).
struct ServerOptions: Equatable, Sendable {
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 7742
    static let defaultMaxConnections = 4
    static let defaultMaxBodyBytes = 104_857_600

    /// Interface to bind.
    let host: String
    /// TCP port to bind; 0 asks the OS for an ephemeral port (tests).
    let port: Int
    /// Maximum number of `mockingbird` subprocesses alive at once.
    let maxConnections: Int
    /// The `mockingbird` CLI to spawn.
    let mockingbird: URL
    /// Largest `POST /analyze` body accepted, in bytes.
    let maxBodyBytes: Int
    /// Where encoded uploads are staged for the CLI. Not a command-line flag; tests point it
    /// at a private directory so they can assert nothing is left behind.
    let temporaryDirectory: URL

    init(
        host: String = ServerOptions.defaultHost,
        port: Int = ServerOptions.defaultPort,
        maxConnections: Int = ServerOptions.defaultMaxConnections,
        mockingbird: URL,
        maxBodyBytes: Int = ServerOptions.defaultMaxBodyBytes,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.host = host
        self.port = port
        self.maxConnections = maxConnections
        self.mockingbird = mockingbird
        self.maxBodyBytes = maxBodyBytes
        self.temporaryDirectory = temporaryDirectory
    }
}
