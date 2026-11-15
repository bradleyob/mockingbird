import CoreAudio

/// Enumerates capture devices through the CoreAudio HAL.
///
/// Reading device properties does not start capture, so it never raises the macOS
/// microphone permission prompt.
enum CaptureDeviceDirectory {
    /// Every device with at least one input channel, in HAL order.
    static func inputDevices() -> [CaptureDevice] {
        allDeviceIDs().compactMap { id in
            guard inputChannelCount(of: id) > 0, let name = name(of: id), !name.isEmpty else { return nil }
            return CaptureDevice(id: id, name: name)
        }
    }

    /// The first input device whose name is exactly `name`.
    static func inputDevice(named name: String) -> CaptureDevice? {
        inputDevices().first { $0.name == name }
    }

    // MARK: - Private

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, base)
        }
        guard status == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
    }

    private static func inputChannelCount(of id: AudioDeviceID) -> Int {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var property = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
