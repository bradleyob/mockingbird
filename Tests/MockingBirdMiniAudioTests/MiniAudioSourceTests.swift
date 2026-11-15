import Foundation
import MockingBirdCore
import Testing
@testable import AudioSourceMiniAudio

/// Capture through miniaudio's null backend: real-time silence, no hardware, no permission
/// prompt. Real ALSA/PipeWire/CoreAudio capture is not testable headless.
@Suite(.timeLimit(.minutes(1))) struct MiniAudioSourceTests {
    @Test func nullBackendDeliversAudioInRealTimeAndFinishesOnStop() async throws {
        let source = MiniAudioSource(deviceName: nil, backend: .null)
        let stream = try source.start(sampleRate: 44100)
        let started = ContinuousClock.now

        var received = 0
        for try await chunk in stream {
            received += chunk.count
            if received >= 22050 || ContinuousClock.now - started > .seconds(2) {
                break
            }
        }
        #expect(received >= 22050)
        #expect(ContinuousClock.now - started <= .seconds(2))

        source.stop()
        var afterStop = 0
        for try await chunk in stream {
            afterStop += chunk.count
        }
        #expect(afterStop < 44100, "stream must finish promptly after stop()")
    }

    @Test func stopEndsAStreamThatIsBeingIterated() async throws {
        let source = MiniAudioSource(deviceName: nil, backend: .null)
        let stream = try source.start(sampleRate: 48000)
        let consumer = Task {
            var count = 0
            for try await chunk in stream {
                count += chunk.count
            }
            return count
        }
        try await Task.sleep(for: .milliseconds(200))
        source.stop()
        let count = try await consumer.value
        #expect(count > 0)
    }

    @Test func namedNullDeviceIsFound() async throws {
        let names = try MiniAudioSource.inputDeviceNames(backend: .null)
        let name = try #require(names.first)
        let source = MiniAudioSource(deviceName: name, backend: .null)
        _ = try source.start(sampleRate: 44100)
        source.stop()
    }

    @Test func unknownDeviceNameIsDeviceUnavailable() {
        let source = MiniAudioSource(deviceName: "no-such-device-xyz", backend: .null)
        #expect {
            try source.start(sampleRate: 44100)
        } throws: { error in
            guard case .deviceUnavailable = error as? AudioSourceError else { return false }
            return true
        }
    }
}
