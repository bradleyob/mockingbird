@preconcurrency import AVFoundation
import MockingBirdCore
import os

/// Captures live microphone audio using `AVAudioEngine`.
///
/// Delivers mono Float32 samples at the requested sample rate via
/// `AsyncThrowingStream`. Install permission (`NSMicrophoneUsageDescription`)
/// in the app's `Info.plist` before use.
public final class AVFoundationSource: AudioSource {
    private let engine = AVAudioEngine()
    // OSAllocatedUnfairLock protects the continuation so the installTap callback
    // (arbitrary thread) and stop() (caller thread) can both access it safely.
    private let continuationBox = OSAllocatedUnfairLock<AsyncThrowingStream<[Float], Error>.Continuation?>(initialState: nil)

    public init() {}

    public func start(sampleRate: Double) throws -> AsyncThrowingStream<[Float], Error> {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioSourceError.formatUnsupported
        }

        let stream = AsyncThrowingStream<[Float], Error> { [continuationBox] cont in
            continuationBox.withLockUnchecked { $0 = cont }
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [continuationBox] buffer, _ in
            continuationBox.withLockUnchecked { continuation in
                guard let continuation else { return }

                guard
                    let converter = AVAudioConverter(from: inputFormat, to: targetFormat),
                    let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: AVAudioFrameCount(
                            Double(buffer.frameLength) * sampleRate / inputFormat.sampleRate
                        )
                    )
                else {
                    continuation.finish(throwing: AudioSourceError.formatUnsupported)
                    return
                }

                var conversionError: NSError?
                let inputBuffer = buffer
                let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                guard status != .error, let channelData = convertedBuffer.floatChannelData else {
                    continuation.finish(throwing: AudioSourceError.unknown(
                        conversionError?.localizedDescription ?? "conversion failed"
                    ))
                    return
                }

                let frameCount = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                continuation.yield(samples)
            }
        }

        do {
            try engine.start()
        } catch {
            throw AudioSourceError.deviceUnavailable
        }

        return stream
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuationBox.withLockUnchecked { cont in
            cont?.finish()
            cont = nil
        }
    }
}
