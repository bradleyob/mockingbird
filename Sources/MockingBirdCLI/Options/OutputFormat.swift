/// How `mockingbird` renders each `KeyResult` on stdout.
enum OutputFormat: String, CaseIterable, Equatable, Sendable {
    /// One `KeyResult` JSON object per line, keys sorted.
    case json
    /// Tab-separated `timestamp`, `key scaleName`, `confidence`, alternates.
    case line
}
