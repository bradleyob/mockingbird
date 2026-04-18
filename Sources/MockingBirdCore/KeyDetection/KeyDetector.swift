import Accelerate

/// Correlates a `ChromaVector` against a `ProfileLibrary` and returns a `KeyResult`.
///
/// Uses Pearson correlation. Scores are normalized to [0, 1] by rescaling from
/// [min_score, max_score] so that the winning profile always has confidence = 1
/// and relative distances are preserved.
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
            (profile: profile, score: pearsonCorrelation(chroma.bins, profile.weights))
        }

        let sorted = scores.sorted { $0.score > $1.score }

        guard let best = sorted.first else {
            // Library was empty — this is an invariant violation caught at init.
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

    /// Pearson correlation coefficient between two 12-element vectors.
    private func pearsonCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        let n = vDSP_Length(12)

        var xMean: Float = 0
        var yMean: Float = 0
        vDSP_meanv(x, 1, &xMean, n)
        vDSP_meanv(y, 1, &yMean, n)

        var xCentered = [Float](repeating: 0, count: 12)
        var yCentered = [Float](repeating: 0, count: 12)
        var negXMean = -xMean
        var negYMean = -yMean
        vDSP_vsadd(x, 1, &negXMean, &xCentered, 1, n)
        vDSP_vsadd(y, 1, &negYMean, &yCentered, 1, n)

        var dotProduct: Float = 0
        vDSP_dotpr(xCentered, 1, yCentered, 1, &dotProduct, n)

        var xSumSq: Float = 0
        var ySumSq: Float = 0
        vDSP_svesq(xCentered, 1, &xSumSq, n)
        vDSP_svesq(yCentered, 1, &ySumSq, n)

        let denominator = (xSumSq * ySumSq).squareRoot()
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }
}
