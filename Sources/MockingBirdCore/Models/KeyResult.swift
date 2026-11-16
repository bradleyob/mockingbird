import Foundation

/// The result of one key detection pass, emitted once per hop by `AnalysisPipeline`.
///
/// Depending on the pipeline's `ChromaAggregation`, it reflects one window, every window
/// so far, or a rolling span. Encodes (with `.sortedKeys`) as
/// `{"alternates":[…],"category":"major","confidence":0.924,"key":"C","scaleName":"major","timestamp":3.99}`.
public struct KeyResult: Equatable, Codable, Sendable {
    /// Detected root pitch class.
    public let key: PitchClass
    /// Human-readable scale name, e.g. "major", "dorian", "blues".
    public let scaleName: String
    /// Broad scale category.
    public let category: ScaleCategory
    /// Pearson correlation with the winning profile, clamped to [0, 1]. Tonal material
    /// typically scores 0.8–0.95, white noise about 0.45, silence 0.
    public let confidence: Float
    /// Up to `AudioConfig.numAlternates` runner-up candidates, sorted by confidence descending.
    public let alternates: [KeyResult.Alternate]
    /// Seconds of audio consumed at the end of the analysed window:
    /// `(windowIndex * hopSize + windowSize) / sampleRate`. Audio time, not wall-clock.
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
