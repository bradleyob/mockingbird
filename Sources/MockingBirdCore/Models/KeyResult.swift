import Foundation

/// The result of a key detection pass over one analysis window.
public struct KeyResult: Equatable, Codable, Sendable {
    /// Detected root pitch class.
    public let key: PitchClass
    /// Human-readable scale name, e.g. "major", "dorian", "blues".
    public let scaleName: String
    /// Broad scale category.
    public let category: ScaleCategory
    /// Confidence score in [0, 1]. Higher is more certain.
    public let confidence: Float
    /// Up to `AudioConfig.numAlternates` runner-up candidates, sorted by confidence descending.
    public let alternates: [KeyResult.Alternate]
    /// Timestamp of the analysis window (seconds from stream start).
    public let timestamp: TimeInterval

    public init(
        key: PitchClass,
        scaleName: String,
        category: ScaleCategory,
        confidence: Float,
        alternates: [Alternate] = [],
        timestamp: TimeInterval = 0
    ) {
        self.key = key
        self.scaleName = scaleName
        self.category = category
        self.confidence = min(max(confidence, 0), 1)
        self.alternates = alternates
        self.timestamp = timestamp
    }

    /// A runner-up candidate from the same detection pass.
    public struct Alternate: Equatable, Codable, Sendable {
        public let key: PitchClass
        public let scaleName: String
        public let category: ScaleCategory
        public let confidence: Float

        public init(key: PitchClass, scaleName: String, category: ScaleCategory, confidence: Float) {
            self.key = key
            self.scaleName = scaleName
            self.category = category
            self.confidence = min(max(confidence, 0), 1)
        }
    }
}

extension KeyResult: CustomStringConvertible {
    public var description: String {
        "\(key) \(scaleName) (confidence: \(String(format: "%.2f", confidence)))"
    }
}
