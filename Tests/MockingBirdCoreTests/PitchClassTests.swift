import Foundation
import Testing
@testable import MockingBirdCore

@Suite("PitchClass")
struct PitchClassTests {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    @Test("has 12 sharps-only cases in chromatic order")
    func twelveSharps() {
        #expect(PitchClass.allCases.count == 12)
        #expect(PitchClass.allCases.map(\.description) == Self.names)
        #expect(PitchClass.allCases.map(\.rawValue) == Array(0..<12))
    }

    @Test("encodes as its name string", arguments: PitchClass.allCases)
    func encodesAsString(pitchClass: PitchClass) throws {
        let data = try JSONEncoder().encode([pitchClass])
        #expect(String(decoding: data, as: UTF8.self) == "[\"\(Self.names[pitchClass.rawValue])\"]")
        #expect(try JSONDecoder().decode([PitchClass].self, from: data) == [pitchClass])
    }

    @Test("decodes legacy integers 0–11")
    func decodesLegacyIntegers() throws {
        let decoded = try JSONDecoder().decode([PitchClass].self, from: Data("[0, 1, 11]".utf8))
        #expect(decoded == [.c, .cSharp, .b])
    }

    @Test("rejects unknown names and out-of-range integers", arguments: ["[\"H\"]", "[\"Db\"]", "[12]", "[-1]", "[1.5]"])
    func rejectsInvalid(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PitchClass].self, from: Data(json.utf8))
        }
    }

    @Test("transposition wraps in both directions")
    func transposition() {
        #expect(PitchClass.a.transposed(by: 3) == .c)
        #expect(PitchClass.c.transposed(by: -1) == .b)
        #expect(PitchClass.d.transposed(by: 26) == .e)
        #expect(PitchClass.d.transposed(by: -26) == .c)
    }
}
