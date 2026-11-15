import Foundation
@testable import MockingBirdCLI
import MockingBirdCore
import Testing

@Suite struct ResultFormatterTests {
    static let result = KeyResult(
        key: .c,
        scaleName: "major",
        category: .major,
        confidence: 0.924,
        alternates: [
            .init(key: .c, scaleName: "major pentatonic", category: .pentatonic, confidence: 0.881),
            .init(key: .g, scaleName: "mixolydian", category: .mode, confidence: 0.842),
        ],
        timestamp: 3.99
    )

    @Test func lineFormatIsExact() throws {
        let line = try ResultFormatter(format: .line).format(Self.result)
        #expect(line == "3.99\tC major\t0.924\tC major pentatonic 0.881; G mixolydian 0.842")
    }

    @Test func lineFormatWithoutAlternatesKeepsFourFields() throws {
        let result = KeyResult(key: .fSharp, scaleName: "minor", category: .minor, confidence: 0.5, timestamp: 0.0929)
        let line = try ResultFormatter(format: .line).format(result)
        #expect(line == "0.09\tF# minor\t0.500\t")
        #expect(line.split(separator: "\t", omittingEmptySubsequences: false).count == 4)
    }

    @Test func jsonIsOneSortedLineThatRoundTrips() throws {
        let json = try ResultFormatter(format: .json).format(Self.result)
        #expect(!json.contains("\n"))
        #expect(json.hasPrefix(#"{"alternates":[{"category":"pentatonic","confidence":"#))
        #expect(json.contains(#""scaleName":"major","timestamp":3.99}"#))
        let decoded = try JSONDecoder().decode(KeyResult.self, from: Data(json.utf8))
        #expect(decoded == Self.result)
    }
}
