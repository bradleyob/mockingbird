/// A chromatic pitch class. Sharps only; 12 cases, index 0 = C.
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
        return PitchClass(rawValue: index)!
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
