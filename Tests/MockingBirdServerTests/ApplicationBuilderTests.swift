import Foundation
import Testing
@testable import MockingBirdServer

@Suite struct ApplicationBuilderTests {
    @Test func healthReturnsOk() async throws {
        try await LiveServer.run(ApplicationBuilder(options: .testing())) { port in
            let response = try await LiveServer.request(port: port, "/health")
            #expect(response.status == .ok)
            #expect(String(buffer: response.body) == "ok")
        }
    }
}
