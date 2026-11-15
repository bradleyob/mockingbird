#if os(macOS)
import Foundation
import MockingBirdCore
import MockingBirdTestSupport
import Testing

/// `mockingbird <file>` on container formats decoded by AVFoundation.
@Suite struct DecodedFileTests {
    /// A C-major cadence as a 16-bit mono WAV at `sampleRate`.
    static func cadenceWAV(sampleRate: Int = 44100) throws -> URL {
        let samples = ToneSynth.majorCadence(root: 48, sampleRate: Double(sampleRate))
        return try AudioFixture.writeTemporary(AudioFixture.wav16(samples, sampleRate: sampleRate), fileExtension: "wav")
    }

    /// Runs `/usr/bin/afconvert` and returns the output file.
    static func afconvert(_ input: URL, fileExtension: String, _ arguments: [String]) throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("mockingbird-test-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = arguments + [input.path, output.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "afconvert \(arguments) failed")
        return output
    }

    private func expectCMajorRoot(_ url: URL) throws {
        let run = try CLIInvocation.run([url.path])
        #expect(run.status == 0, "stderr: \(run.stderr)")
        #expect(run.stderr.isEmpty)
        let results = try run.results()
        #expect(results.count == 1)
        #expect(results.first?.key == .c)
    }

    @Test func wav() throws {
        let wav = try Self.cadenceWAV()
        defer { try? FileManager.default.removeItem(at: wav) }
        try expectCMajorRoot(wav)
    }

    @Test(arguments: [
        ("aiff", ["-f", "AIFF", "-d", "BEI16"]),
        ("m4a", ["-f", "m4af", "-d", "aac"]),
        ("wav", ["-f", "WAVE", "-d", "LEI16", "-c", "2"]),
    ])
    func convertedFormats(fileExtension: String, arguments: [String]) throws {
        let wav = try Self.cadenceWAV()
        defer { try? FileManager.default.removeItem(at: wav) }
        let converted = try Self.afconvert(wav, fileExtension: fileExtension, arguments)
        defer { try? FileManager.default.removeItem(at: converted) }
        try expectCMajorRoot(converted)
    }

    @Test func lowerSampleRateIsResampled() throws {
        let wav = try Self.cadenceWAV(sampleRate: 22050)
        defer { try? FileManager.default.removeItem(at: wav) }
        try expectCMajorRoot(wav)
    }

    @Test func undecodableFileExitsFour() throws {
        let url = try AudioFixture.writeTemporary(Data("this is not audio\n".utf8), fileExtension: "wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try CLIInvocation.run([url.path])
        #expect(run.status == 4)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.hasPrefix("mockingbird: error:"))
        #expect(run.stderr.contains(url.path))
    }
}
#endif
