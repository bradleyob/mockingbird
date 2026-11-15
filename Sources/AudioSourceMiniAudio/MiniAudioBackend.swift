import CMiniAudio

/// Which miniaudio backend a capture uses.
enum MiniAudioBackend: Sendable {
    /// The platform's normal order (CoreAudio on macOS; PulseAudio, ALSA, JACK on Linux).
    case platformDefault
    /// miniaudio's null device: real-time silence with no hardware. Used by tests.
    case null

    var bridgeValue: mb_backend {
        switch self {
        case .platformDefault: return MB_BACKEND_DEFAULT
        case .null: return MB_BACKEND_NULL
        }
    }
}
