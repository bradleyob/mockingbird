import Foundation
import Testing
@testable import MockingBirdCore

@Suite("KeyResult")
struct KeyResultTests {
    static let golden = #"{"alternates":[{"category":"pentatonic","confidence":0.881,"key":"C","scaleName":"major pentatonic"}],"category":"major","confidence":0.924,"key":"C","scaleName":"major","timestamp":3.99}"#

    static let fixture = KeyResult(
        key: .c,
        scaleName: "major",
        category: .major,
        confidence: 0.924,
        alternates: [.init(key: .c, scaleName: "major pentatonic", category: .pentatonic, confidence: 0.881)],
        timestamp: 3.99
    )

    @Test("encodes with sorted keys to exactly the contract shape")
    func goldenEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(Self.fixture), as: UTF8.self)
        #expect(json == Self.golden)
    }

    @Test("decodes the contract shape and round-trips")
    func roundTrip() throws {
        let decoded = try JSONDecoder().decode(KeyResult.self, from: Data(Self.golden.utf8))
        #expect(decoded == Self.fixture)
    }

    @Test("confidence is clamped to [0, 1]")
    func confidenceClamped() {
        #expect(KeyResult(key: .c, scaleName: "major", category: .major, confidence: 1.7).confidence == 1)
        #expect(KeyResult(key: .c, scaleName: "major", category: .major, confidence: -0.2).confidence == 0)
        #expect(KeyResult.Alternate(key: .c, scaleName: "major", category: .major, confidence: 2).confidence == 1)
    }
}
