/// Combines per-window chroma energy according to a `ChromaAggregation` mode.
///
/// Works on un-normalised energy from `ChromaExtractor.extractEnergy(_:)`, so louder
/// windows weigh more than quiet ones. A value type: `adding(_:)` returns the updated
/// accumulator and the aggregate to detect on, leaving the original untouched.
public struct ChromaAccumulator: Sendable {
    /// The aggregation mode this accumulator implements.
    public let aggregation: ChromaAggregation
    /// Running sum for `.cumulative`.
    private let total: [Float]
    /// Most recent windows, oldest first, for `.rolling`.
    private let recent: [[Float]]

    /// - Parameter aggregation: Mode to implement. `.rolling(windows:)` needs `windows >= 1`.
    public init(aggregation: ChromaAggregation) {
        if case .rolling(let windows) = aggregation {
            precondition(windows >= 1, "rolling aggregation needs at least 1 window, got \(windows)")
        }
        self.init(aggregation: aggregation, total: [Float](repeating: 0, count: 12), recent: [])
    }

    private init(aggregation: ChromaAggregation, total: [Float], recent: [[Float]]) {
        self.aggregation = aggregation
        self.total = total
        self.recent = recent
    }

    /// Adds one window's energy.
    ///
    /// - Parameter energy: 12-bin chroma energy of the newest window.
    /// - Returns: The updated accumulator and the aggregated 12-bin energy it now represents.
    public func adding(_ energy: [Float]) -> (accumulator: ChromaAccumulator, aggregate: [Float]) {
        precondition(energy.count == 12, "chroma energy must have 12 bins, got \(energy.count)")
        switch aggregation {
        case .perWindow:
            return (self, energy)
        case .cumulative:
            let sum = zip(total, energy).map { $0 + $1 }
            return (ChromaAccumulator(aggregation: aggregation, total: sum, recent: []), sum)
        case .rolling(let windows):
            let kept = Array((recent + [energy]).suffix(windows))
            // Re-summed every hop rather than updated incrementally, so Float error
            // cannot drift over a long live stream.
            let sum = kept.reduce([Float](repeating: 0, count: 12)) { partial, window in
                zip(partial, window).map { $0 + $1 }
            }
            return (ChromaAccumulator(aggregation: aggregation, total: total, recent: kept), sum)
        }
    }
}
