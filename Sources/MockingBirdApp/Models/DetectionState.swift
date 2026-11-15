/// What the app is doing right now. Drives every view.
enum DetectionState: Equatable, Sendable {
    /// Nothing running.
    case idle
    /// Waiting for the user to answer the microphone permission prompt.
    case requestingPermission
    /// Live microphone capture is running; results update every hop.
    case listening
    /// A file with the given display name is being analysed.
    case analyzingFile(String)
    /// The file with the given display name has been analysed; `result` holds the answer.
    case finished(String)
    /// The last operation failed; the message is shown to the user.
    case failed(String)
}
