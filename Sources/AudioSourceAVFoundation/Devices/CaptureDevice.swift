import CoreAudio

/// A CoreAudio device that has at least one input stream.
struct CaptureDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
}
