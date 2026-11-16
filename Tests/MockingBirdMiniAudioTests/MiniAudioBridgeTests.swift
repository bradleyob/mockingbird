import CMiniAudio
import Foundation
import MockingBirdTestSupport
import Testing

/// Direct checks of the mb_ C bridge, headless: null backend and the file decoder only.
@Suite struct MiniAudioBridgeTests {
    @Test func nullBackendListsOneCaptureDevice() {
        var names = [CChar](repeating: 0, count: 8 * Int(MB_DEVICE_NAME_CAPACITY))
        var count: UInt32 = 0
        let result = mb_list_capture_devices(MB_BACKEND_NULL, &names, 8, &count)
        #expect(result == MB_SUCCESS)
        #expect(count >= 1)
        let first = String(decoding: names.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #expect(!first.isEmpty)
    }

    @Test func unknownDeviceNameIsDeviceNotFound() {
        var capture: OpaquePointer?
        let result = mb_capture_create(MB_BACKEND_NULL, "no-such-device-xyz", 44100, 44100, &capture)
        #expect(result == MB_DEVICE_NOT_FOUND)
        #expect(capture == nil)
        #expect(String(cString: mb_result_description(result)).isEmpty == false)
    }

    @Test func nullCaptureFillsTheRingBuffer() async throws {
        var capture: OpaquePointer?
        #expect(mb_capture_create(MB_BACKEND_NULL, nil, 44100, 44100, &capture) == MB_SUCCESS)
        let handle = try #require(capture)
        defer { mb_capture_destroy(handle) }
        #expect(mb_capture_start(handle) == MB_SUCCESS)
        try await Task.sleep(for: .milliseconds(300))
        var buffer = [Float](repeating: 1, count: 44100)
        var read: UInt32 = 0
        #expect(mb_capture_read(handle, &buffer, UInt32(buffer.count), &read) == MB_SUCCESS)
        #expect(read > 0)
        #expect(buffer.prefix(Int(read)).allSatisfy { $0 == 0 })
        #expect(mb_capture_stop(handle) == MB_SUCCESS)
    }

    @Test func decoderReadsAWavAndRejectsGarbage() throws {
        let wav = try AudioFixture.writeTemporary(AudioFixture.wav16(ToneSynth.chord([60], duration: 1)), fileExtension: "wav")
        let garbage = try AudioFixture.writeTemporary(Data(repeating: 0x41, count: 5000), fileExtension: "wav")
        defer {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: garbage)
        }

        var decoder: OpaquePointer?
        #expect(mb_decoder_open(wav.path, 44100, &decoder) == MB_SUCCESS)
        let handle = try #require(decoder)
        defer { mb_decoder_close(handle) }
        var buffer = [Float](repeating: 0, count: 4096)
        var total = 0
        while true {
            var read: UInt32 = 0
            #expect(mb_decoder_read(handle, &buffer, UInt32(buffer.count), &read) == MB_SUCCESS)
            if read == 0 { break }
            total += Int(read)
        }
        #expect(total == 44100)

        var rejected: OpaquePointer?
        #expect(mb_decoder_open(garbage.path, 44100, &rejected) != MB_SUCCESS)
        #expect(rejected == nil)
        #expect(mb_decoder_open("/nonexistent/file.wav", 44100, &rejected) != MB_SUCCESS)
    }
}
