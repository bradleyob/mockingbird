import Foundation
import HummingbirdTesting
import Testing
@testable import MockingBirdServer

@Suite struct ApplicationBuilderTests {
    @Test func healthReturnsOk() async throws {
        let builder = ApplicationBuilder(options: .testing())
        try await builder.build().test(.live) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "ok")
            }
        }
    }
}
