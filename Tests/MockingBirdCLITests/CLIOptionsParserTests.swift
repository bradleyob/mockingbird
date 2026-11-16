@testable import MockingBirdCLI
import Testing

@Suite struct CLIOptionsParserTests {
    private func parse(_ arguments: String...) throws -> CLIOptions {
        try CLIOptionsParser.parse(arguments)
    }

    /// Asserts that parsing fails with a usage error whose message mentions `fragment`.
    private func expectUsageError(_ arguments: [String], mentioning fragment: String) {
        do {
            let options = try CLIOptionsParser.parse(arguments)
            Issue.record("expected a usage error for \(arguments), parsed \(options)")
        } catch {
            #expect(error.message.contains(fragment), "message '\(error.message)' should mention '\(fragment)'")
        }
    }

    @Test func defaults() throws {
        let options = try parse()
        #expect(options == CLIOptions())
        #expect(options.sampleRate == 44100)
        #expect(options.windowSize == 4096)
        #expect(options.hopSize == 2048)
        #expect(options.alternates == 3)
        #expect(options.zeroPad == false)
        #expect(options.profilesPath == nil)
        #expect(options.device == nil)
        #expect(options.continuous == false)
        #expect(options.format == .json)
        #expect(options.duration == nil)
        #expect(options.listDevices == false)
        #expect(options.file == nil)
        #expect(options.showHelp == false)
        #expect(options.showVersion == false)
    }

    @Test func everyFlag() throws {
        let options = try parse(
            "--sample-rate", "48000", "--window-size", "8192", "--hop-size", "1024",
            "--alternates", "5", "--zero-pad", "--profiles", "/tmp/p.json", "--device", "default",
            "--continuous", "--format", "line", "--duration", "2.5", "--list-devices",
            "--help", "--version"
        )
        #expect(options.sampleRate == 48000)
        #expect(options.windowSize == 8192)
        #expect(options.hopSize == 1024)
        #expect(options.alternates == 5)
        #expect(options.zeroPad)
        #expect(options.profilesPath == "/tmp/p.json")
        #expect(options.device == "default")
        #expect(options.continuous)
        #expect(options.format == .line)
        #expect(options.duration == 2.5)
        #expect(options.listDevices)
        #expect(options.showHelp)
        #expect(options.showVersion)
    }

    @Test func equalsSignForm() throws {
        let options = try parse("--hop-size=512", "--format=line")
        #expect(options.hopSize == 512)
        #expect(options.format == .line)
    }

    @Test func positionalFile() throws {
        #expect(try parse("song.wav").file == "song.wav")
        #expect(try parse("--alternates", "1", "song.wav").file == "song.wav")
    }

    @Test func fileFlag() throws {
        #expect(try parse("--file", "song.raw").file == "song.raw")
    }

    @Test func twoPositionalFiles() {
        expectUsageError(["a.wav", "b.wav"], mentioning: "b.wav")
        expectUsageError(["--file", "a.wav", "b.wav"], mentioning: "a.wav")
        expectUsageError(["a.wav", "--file", "b.wav"], mentioning: "--file")
    }

    @Test func unknownFlag() {
        expectUsageError(["--frobnicate"], mentioning: "--frobnicate")
        expectUsageError(["-x"], mentioning: "-x")
    }

    @Test func missingValue() {
        expectUsageError(["--window-size"], mentioning: "--window-size")
        expectUsageError(["--profiles"], mentioning: "--profiles")
        expectUsageError(["--sample-rate", "--zero-pad"], mentioning: "--sample-rate")
    }

    @Test func flagsThatTakeNoValueRejectOne() {
        expectUsageError(["--zero-pad=yes"], mentioning: "--zero-pad")
    }

    @Test func nonNumericValue() {
        expectUsageError(["--sample-rate", "fast"], mentioning: "--sample-rate")
        expectUsageError(["--alternates", "three"], mentioning: "--alternates")
        expectUsageError(["--duration", "long"], mentioning: "--duration")
    }

    @Test func nonPositiveValues() {
        expectUsageError(["--sample-rate", "0"], mentioning: "--sample-rate")
        expectUsageError(["--hop-size", "0"], mentioning: "--hop-size")
        expectUsageError(["--duration", "0"], mentioning: "--duration")
        expectUsageError(["--duration", "-1"], mentioning: "--duration")
    }

    @Test func windowSizeNotAPowerOfTwo() {
        expectUsageError(["--window-size", "1000"], mentioning: "--window-size")
        expectUsageError(["--window-size", "0"], mentioning: "--window-size")
    }

    @Test func hopLargerThanWindow() {
        expectUsageError(["--window-size", "1024", "--hop-size", "2048"], mentioning: "--hop-size")
        // Order of flags does not matter: the check runs after all flags are read.
        expectUsageError(["--hop-size", "8192"], mentioning: "--hop-size")
    }

    @Test func negativeAlternates() {
        expectUsageError(["--alternates", "-1"], mentioning: "--alternates")
    }

    @Test func zeroAlternatesIsAllowed() throws {
        #expect(try parse("--alternates", "0").alternates == 0)
    }

    @Test func unknownFormat() {
        expectUsageError(["--format", "xml"], mentioning: "--format")
    }

    @Test func emptyDeviceName() {
        expectUsageError(["--device", ""], mentioning: "--device")
    }
}
