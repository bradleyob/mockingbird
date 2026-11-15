/// A chromatic pitch class. Sharps only; 12 cases, index 0 = C.
///
/// Encodes as its name (`"C"`, `"C#"`, … `"B"`). Decoding accepts those names and, for
/// compatibility with early output, the integers 0–11.
public enum PitchClass: Int, CaseIterable, Codable, Sendable {
    case c = 0
    case cSharp
    case d
    case dSharp
    case e
    case f
    case fSharp
    case g
    case gSharp
    case a
    case aSharp
    case b

    /// Returns the pitch class `semitones` above this one (wraps at 12).
    public func transposed(by semitones: Int) -> PitchClass {
        let index = (rawValue + semitones % 12 + 12) % 12
        return Self.allCases[index]
    }

    /// The pitch class with the given name (`"C"` … `"B"`, sharps only), or `nil`.
    public init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.description == name }) else { return nil }
        self = match
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard let pitchClass = PitchClass(name: name) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unknown pitch class '\(name)'; expected C, C#, … B")
            }
            self = pitchClass
            return
        }
        let index = try container.decode(Int.self)
        guard let pitchClass = PitchClass(rawValue: index) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "pitch class index \(index) is outside 0...11")
        }
        self = pitchClass
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension PitchClass: CustomStringConvertible {
    public var description: String {
        switch self {
        case .c:      return "C"
        case .cSharp: return "C#"
        case .d:      return "D"
        case .dSharp: return "D#"
        case .e:      return "E"
        case .f:      return "F"
        case .fSharp: return "F#"
        case .g:      return "G"
        case .gSharp: return "G#"
        case .a:      return "A"
        case .aSharp: return "A#"
        case .b:      return "B"
        }
    }
}
