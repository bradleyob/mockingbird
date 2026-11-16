/// Correlates a chroma vector against a `ProfileLibrary` and returns a `KeyResult`.
///
/// Uses Pearson correlation (Krumhansl–Schmuckler). Measured on synthetic material,
/// cosine similarity against the near-identical profiles of a large library always
/// favoured the sparse pentatonic profiles and gave white noise a score of 0.95;
/// Pearson subtracts each vector's mean, so a flat (noisy) spectrum scores low and
/// tonal material scores high.
///
/// The winner's and each alternate's `confidence` is its correlation r clamped to
/// [0, 1]. It is an absolute score, comparable across windows and inputs: tonal
/// material is typically 0.8–0.95, white noise around 0.45, silence 0.
///
/// `detect(_:timestamp:)` is a pure function — no internal mutable state.
public struct KeyDetector: Sendable {
    private let library: ProfileLibrary
    private let numAlternates: Int
    /// Each profile's weights with the mean removed and scaled to unit norm, so a
    /// correlation is one dot product with the (likewise centred) chroma.
    private let centredProfiles: [[Float]]

    public init(library: ProfileLibrary, numAlternates: Int) {
        precondition(!library.profiles.isEmpty,
                     "KeyDetector requires a non-empty ProfileLibrary")
        precondition(numAlternates >= 0, "numAlternates must be non-negative")
        self.library = library
        self.numAlternates = numAlternates
        self.centredProfiles = library.profiles.map { Self.centredUnit($0.weights) }
    }

    /// Detects the most likely key in the given chroma vector.
    ///
    /// - Parameter chroma: 12-bin chroma (any positive scale; correlation ignores it).
    /// - Parameter timestamp: Seconds of audio consumed, forwarded to `KeyResult`.
    /// - Returns: Best-match `KeyResult` with up to `numAlternates` runners-up, sorted by
    ///   confidence descending. Ties keep library order.
    public func detect(_ chroma: ChromaVector, timestamp: Double = 0) -> KeyResult {
        let centredChroma = Self.centredUnit(chroma.bins)
        let ranked = centredProfiles.enumerated()
            .map { (index: $0.offset, score: Self.dot(centredChroma, $0.element)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        guard let best = ranked.first else {
            preconditionFailure("ProfileLibrary was empty at detection time")
        }

        let alternates = ranked.dropFirst().prefix(numAlternates).map { candidate in
            let profile = library.profiles[candidate.index]
            return KeyResult.Alternate(
                key: profile.root,
                scaleName: profile.scaleName,
                category: profile.category,
                confidence: candidate.score
            )
        }

        let winner = library.profiles[best.index]
        return KeyResult(
            key: winner.root,
            scaleName: winner.scaleName,
            category: winner.category,
            confidence: best.score,
            alternates: Array(alternates),
            timestamp: timestamp
        )
    }

    // MARK: - Private

    /// `values` minus its mean, scaled to unit L2 norm. A constant vector (including
    /// silence) has no variance and becomes all zeros, so it correlates 0 with everything.
    private static func centredUnit(_ values: [Float]) -> [Float] {
        let mean = values.reduce(0, +) / Float(values.count)
        let centred = values.map { $0 - mean }
        let norm = centred.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 1e-12 else { return [Float](repeating: 0, count: values.count) }
        return centred.map { $0 / norm }
    }

    private static func dot(_ x: [Float], _ y: [Float]) -> Float {
        var sum: Float = 0
        for index in 0..<x.count {
            sum += x[index] * y[index]
        }
        return sum
    }
}
