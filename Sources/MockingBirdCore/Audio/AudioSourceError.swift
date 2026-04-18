/// Errors that can be thrown by `AudioSource` implementations.
public enum AudioSourceError: Error, Codable, Sendable {
    case permissionDenied
    case deviceUnavailable
    case formatUnsupported
    case deviceDisconnected
    case unknown(String)
}

extension AudioSourceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .permissionDenied:     return "microphone permission denied"
        case .deviceUnavailable:    return "audio device unavailable"
        case .formatUnsupported:    return "audio format not supported"
        case .deviceDisconnected:   return "audio device disconnected"
        case .unknown(let msg):     return "unknown audio error: \(msg)"
        }
    }
}
