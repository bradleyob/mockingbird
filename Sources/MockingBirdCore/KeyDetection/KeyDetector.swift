import Accelerate

/// Correlates a `ChromaVector` against a `ProfileLibrary` and returns a `KeyResult`.
///
/// Uses cosine similarity (dot product of two L2-normalized vectors).
/// Both the chroma vector from `ChromaExtractor` and all profiles in `ProfileLibrary`
/// are already L2-normalized, so the score reduces to a simple dot product in [−1, 1].
/// This matches the Krumhansl-Schmuckler formulation and handles sparse chord input
/// correctly — Pearson correlation subtracts the mean, which unfairly penalizes
/// diatonic profiles when the input has only a few non-zero bins.
///
/// Scores are rescaled to [0, 1] by mapping [min, max] → [0, 1] so that confidence
/// values are comparable across windows and relative distances are preserved.
///
/// `detect(_:timestamp:)` is a pure function — no internal mutable state.
public struct KeyDetector {
    private let library: ProfileLibrary
    private let numAlternates: Int

    public init(library: ProfileLibrary, numAlternates: Int) {
        precondition(!library.profiles.isEmpty,
                     "KeyDetector requires a non-empty ProfileLibrary")
        self.library = library
        self.numAlternates = numAlternates
    }

    /// Detects the most likely key in the given chroma vector.
    ///
    /// - Parameter chroma: L2-normalized 12-bin chroma vector from `ChromaExtractor`.
    /// - Parameter timestamp: Seconds from stream start, forwarded to `KeyResult`.
    /// - Returns: Best-match `KeyResult` with up to `numAlternates` runners-up.
    public func detect(_ chroma: ChromaVector, timestamp: Double = 0) -> KeyResult {
        let scores = library.profiles.map { profile in
            (profile: profile, score: cosineSimilarity(chroma.bins, profile.weights))
        }

        let sorted = scores.sorted { $0.score > $1.score }

        guard let best = sorted.first else {
            preconditionFailure("ProfileLibrary was empty at detection time")
        }

        let minScore = sorted.last?.score ?? 0
        let maxScore = best.score
        let range = maxScore - minScore

        let normalize: (Float) -> Float = { score in
            guard range > 0 else { return 1.0 }
            return (score - minScore) / range
        }

        let alternates = sorted.dropFirst().prefix(numAlternates).map { candidate in
            KeyResult.Alternate(
                key: candidate.profile.root,
                scaleName: candidate.profile.scaleName,
                category: candidate.profile.category,
                confidence: normalize(candidate.score)
            )
        }

        return KeyResult(
            key: best.profile.root,
            scaleName: best.profile.scaleName,
            category: best.profile.category,
            confidence: normalize(best.score),
            alternates: Array(alternates),
            timestamp: timestamp
        )
    }

    // MARK: - Private

    /// Cosine similarity of two L2-normalized 12-element vectors (= their dot product).
    private func cosineSimilarity(_ x: [Float], _ y: [Float]) -> Float {
        var result: Float = 0
        vDSP_dotpr(x, 1, y, 1, &result, vDSP_Length(12))
        return result
    }
}
