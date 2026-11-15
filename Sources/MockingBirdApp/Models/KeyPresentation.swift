import MockingBirdCore

/// What the key display shows for a given state and result. Pure data, so the view's
/// wording and "unsure" rule are tested without rendering.
struct KeyPresentation: Equatable {
    /// Below this confidence a live result is shown muted, as "still listening".
    static let tentativeThreshold: Float = 0.6

    /// Root to show large, e.g. "F#". `nil` when there is nothing to show.
    let keyName: String?
    /// Scale to show under the key, e.g. "minor".
    let scaleName: String?
    /// Winner's confidence in [0, 1].
    let confidence: Float?
    /// Runner-up candidates.
    let alternates: [KeyResult.Alternate]
    /// One line of status beneath the key.
    let status: String
    /// The result is not yet trustworthy; the view mutes it.
    let isTentative: Bool
    /// `status` describes a failure.
    let isError: Bool

    init(state: DetectionState, result: KeyResult?) {
        keyName = result.map { String(describing: $0.key) }
        scaleName = result?.scaleName
        confidence = result?.confidence
        alternates = result?.alternates ?? []

        switch state {
        case .idle:
            status = result == nil ? "Press Listen, or drop an audio file here." : "Stopped."
            isTentative = false
            isError = false
        case .requestingPermission:
            status = "Waiting for microphone access…"
            isTentative = true
            isError = false
        case .listening:
            let unsure = (result?.confidence ?? 0) < Self.tentativeThreshold
            status = unsure ? "Listening…" : "Listening"
            isTentative = unsure
            isError = false
        case .analyzingFile(let name):
            status = "Analysing \(name)…"
            isTentative = true
            isError = false
        case .finished(let name):
            status = name
            isTentative = false
            isError = false
        case .failed(let message):
            status = message
            isTentative = false
            isError = true
        }
    }
}
