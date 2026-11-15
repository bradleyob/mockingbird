import Foundation
import MockingBirdCore

/// The hardware-facing pieces `KeyDetectionViewModel` needs, injected as closures so that
/// tests can substitute synthetic sources and canned permission answers.
///
/// The real implementations (AVFoundation capture, file decoding, the system permission
/// prompt) are wired only in the app entry point.
struct KeyDetectionDependencies: Sendable {
    /// Creates the live capture source used by Listen.
    var makeLiveSource: @Sendable () -> any AudioSource
    /// Creates a decoding source for a dropped or opened file.
    var makeFileSource: @Sendable (URL) -> any AudioSource
    /// Asks for microphone access; returns whether it was granted.
    var requestMicrophoneAccess: @Sendable () async -> Bool
}
