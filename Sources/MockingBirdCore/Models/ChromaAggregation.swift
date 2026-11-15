/// How `AnalysisPipeline` combines per-window chroma before each key detection pass.
///
/// A single 4096-sample window (~93 ms) rarely contains enough of a piece to identify
/// its key, so the pipeline detects against chroma accumulated over time. One
/// `KeyResult` is still emitted per hop in every mode.
public enum ChromaAggregation: Equatable, Codable, Sendable {
    /// Each result reflects only its own analysis window.
    case perWindow
    /// Each result reflects every window since the stream started. The last result
    /// of a finite stream is therefore the result for the whole input.
    case cumulative
    /// Each result reflects the most recent `windows` analysis windows.
    case rolling(windows: Int)
}
