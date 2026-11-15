@preconcurrency import AVFoundation
import AudioToolbox
import MockingBirdCore
import os

/// Captures live audio from a capture device using `AVAudioEngine`.
///
/// Delivers mono Float32 samples at the requested sample rate via
/// `AsyncThrowingStream`. The host app needs `NSMicrophoneUsageDescription`; the first
/// capture from a terminal raises the macOS microphone permission prompt.
public final class AVFoundationSource: AudioSource {
    /// Requested tap buffer size, in input-device frames.
    static let tapFrames: AVAudioFrameCount = 4096
    /// Largest tap buffer accepted; AVAudioEngine treats the requested size as a hint.
    static let maxTapFrames: AVAudioFrameCount = 4 * tapFrames

    private let deviceName: String?
    private let engine = AVAudioEngine()
    // Guards the continuation between start() and stop(); never taken in the tap callback,
    // which captures the continuation directly.
    private let continuationBox = OSAllocatedUnfairLock<AsyncThrowingStream<[Float], Error>.Continuation?>(initialState: nil)

    /// - Parameter deviceName: the capture device's name as listed by
    ///   `inputDeviceNames()`. `nil` or `"default"` selects the system default input.
    public init(deviceName: String? = nil) {
        self.deviceName = deviceName == "default" ? nil : deviceName
    }

    /// Names of the capture devices on this machine, in CoreAudio order.
    ///
    /// Reads device properties only; it never starts capture or prompts for permission.
    public static func inputDeviceNames() -> [String] {
        CaptureDeviceDirectory.inputDevices().map(\.name)
    }

    /// Starts capture and returns a stream of sample chunks.
    ///
    /// - Throws: `AudioSourceError.deviceUnavailable` if the named device does not exist
    ///   (checked before the engine is touched) or the engine cannot start;
    ///   `AudioSourceError.permissionDenied` if microphone access is denied or restricted;
    ///   `AudioSourceError.formatUnsupported` if the device format cannot be converted.
    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let device = try resolveDevice()
        try checkAuthorization()

        let inputNode = engine.inputNode
        if let device {
            try select(device, on: inputNode)
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioSourceError.deviceUnavailable
        }
        let converter = try TapConverter(inputFormat: inputFormat, sampleRate: sampleRate, maxInputFrames: Self.maxTapFrames)

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Float].self)
        continuationBox.withLock { $0 = continuation }
        continuation.onTermination = { [weak self] _ in self?.stopEngine() }

        inputNode.installTap(onBus: 0, bufferSize: Self.tapFrames, format: inputFormat) { buffer, _ in
            switch converter.convert(buffer) {
            case .success(let samples):
                continuation.yield(samples)
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }

        do {
            try engine.start()
        } catch {
            stopEngine()
            continuationBox.withLock { $0 = nil }
            throw AudioSourceError.deviceUnavailable
        }
        return stream
    }

    /// Stops capture and finishes the stream.
    public func stop() {
        stopEngine()
        let continuation = continuationBox.withLock { box in
            defer { box = nil }
            return box
        }
        continuation?.finish()
    }

    // MARK: - Private

    private func resolveDevice() throws(AudioSourceError) -> CaptureDevice? {
        guard let deviceName else { return nil }
        guard let device = CaptureDeviceDirectory.inputDevice(named: deviceName) else {
            throw .deviceUnavailable
        }
        return device
    }

    private func checkAuthorization() throws(AudioSourceError) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            throw .permissionDenied
        case .authorized, .notDetermined:
            // .notDetermined: starting the engine raises the system prompt.
            return
        @unknown default:
            return
        }
    }

    private func select(_ device: CaptureDevice, on inputNode: AVAudioInputNode) throws(AudioSourceError) {
        guard let unit = inputNode.audioUnit else { throw .deviceUnavailable }
        var id = device.id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw .deviceUnavailable }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
