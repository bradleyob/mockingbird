/// A named pitch-class weight profile used for key correlation.
///
/// Weights are a 12-element vector indexed C=0…B=11. The vector should be
/// normalized (L2 norm ≈ 1) so that Pearson correlation scores are comparable
/// across profiles.
public struct ScaleProfile: Equatable, Codable, Sendable {
    /// Human-readable name, e.g. "C major", "A dorian", "F# blues".
    public let name: String
    /// Root pitch class.
    public let root: PitchClass
    /// Broad category.
    public let category: ScaleCategory
    /// Short scale type label, e.g. "major", "dorian", "blues".
    public let scaleName: String
    /// 12-element pitch-class weight vector. Count must equal 12.
    public let weights: [Float]

    public init(
        name: String,
        root: PitchClass,
        category: ScaleCategory,
        scaleName: String,
        weights: [Float]
    ) {
        precondition(weights.count == 12,
                     "ScaleProfile weights count must be 12, got \(weights.count)")
        self.name = name
        self.root = root
        self.category = category
        self.scaleName = scaleName
        self.weights = weights
    }

    /// Returns a new profile transposed by `semitones`, rotating the weight vector accordingly.
    ///
    /// Weights are indexed by absolute pitch class (0=C…11=B), so transposing by N
    /// semitones means the tonic weight (currently at index 0 for C-rooted templates)
    /// must shift RIGHT to index N. Right rotation: prepend the last N elements.
    public func transposed(by semitones: Int) -> ScaleProfile {
        let shift = ((semitones % 12) + 12) % 12
        guard shift != 0 else { return self }
        let split = 12 - shift
        let rotated = Array(weights[split...] + weights[..<split])
        let newRoot = root.transposed(by: semitones)
        return ScaleProfile(
            name: "\(newRoot) \(scaleName)",
            root: newRoot,
            category: category,
            scaleName: scaleName,
            weights: rotated
        )
    }
}
