import MockingBirdCore
#if canImport(AudioSourceAVFoundation)
import AudioSourceAVFoundation
#elseif canImport(AudioSourceMiniAudio)
import AudioSourceMiniAudio
#endif

/// Lists capture devices on this platform, for `--list-devices`.
enum DeviceDirectory {
    /// - Throws: `CLIFailure.runtime` if the platform cannot enumerate devices.
    static func inputDeviceNames() throws(CLIFailure) -> [String] {
        #if canImport(AudioSourceAVFoundation)
        return []
        #else
        do {
            return try MiniAudioSource.inputDeviceNames()
        } catch {
            throw .runtime("cannot list capture devices: \(error)")
        }
        #endif
    }
}
