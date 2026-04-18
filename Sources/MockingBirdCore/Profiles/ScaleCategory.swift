/// Broad classification of a scale type, used for grouping and filtering profiles.
public enum ScaleCategory: String, CaseIterable, Codable, Sendable {
    case major
    case minor
    case mode
    case blues
    case jazz
    case pentatonic
    case symmetric
    case custom
}
