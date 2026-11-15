import Foundation
@testable import MockingBirdServer

extension ServerOptions {
    /// Options for an in-process test server: loopback, ephemeral port, a private temp dir.
    static func testing(
        mockingbird: URL = URL(fileURLWithPath: "/nonexistent/mockingbird"),
        maxConnections: Int = 4,
        maxBodyBytes: Int = ServerOptions.defaultMaxBodyBytes,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> ServerOptions {
        ServerOptions(
            host: "127.0.0.1",
            port: 0,
            maxConnections: maxConnections,
            mockingbird: mockingbird,
            maxBodyBytes: maxBodyBytes,
            temporaryDirectory: temporaryDirectory
        )
    }
}
