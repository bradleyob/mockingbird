import Foundation
import MockingBirdCore
#if canImport(AudioSourceAVFoundation)
import AudioSourceAVFoundation
#elseif canImport(AudioSourceMiniAudio)
import AudioSourceMiniAudio
#endif

/// Builds the `AudioSource` for an `InputSelection` on this platform.
enum AudioSourceFactory {
    /// - Throws: `CLIFailure.unreadableInput` for a file that does not exist or cannot be
    ///   read.
    static func makeSource(for selection: InputSelection) throws(CLIFailure) -> any AudioSource {
        switch selection {
        case .file(let path, let kind):
            guard FileManager.default.isReadableFile(atPath: path) else {
                let reason = FileManager.default.fileExists(atPath: path) ? "permission denied" : "no such file"
                throw .unreadableInput("cannot read input file '\(path)': \(reason)")
            }
            let url = URL(fileURLWithPath: path)
            switch kind {
            case .rawFloat32:
                return FileSource(url: url)
            case .decoded:
                return decodedFileSource(url: url)
            }
        case .standardInput:
            return RawPCMSource(handle: .standardInput)
        case .device(let name):
            return try deviceSource(name: name)
        }
    }

    private static func decodedFileSource(url: URL) -> any AudioSource {
        #if canImport(AudioSourceAVFoundation)
        AVFoundationFileSource(url: url)
        #else
        MiniAudioFileSource(url: url)
        #endif
    }

    private static func deviceSource(name: String?) throws(CLIFailure) -> any AudioSource {
        // Rejecting an unknown name here, before any capture starts, gives a message that
        // names the device and guarantees no microphone permission prompt for a typo.
        if let name {
            let known = try DeviceDirectory.inputDeviceNames()
            guard known.contains(name) else {
                throw .runtime("no capture device named '\(name)'; run mockingbird --list-devices")
            }
        }
        #if canImport(AudioSourceAVFoundation)
        return AVFoundationSource(deviceName: name)
        #else
        return MiniAudioSource(deviceName: name)
        #endif
    }
}
