import Foundation
import MockingBirdCore
import MockingBirdTestSupport
import Testing

/// Runs the real `mockingbird` binary end to end.
///
/// Key assertions check only the root (`key == .c`) and decode JSON instead of matching
/// strings, so they hold both before and after the Core accuracy work lands.
@Suite struct CLIProcessTests {
    static let cadence = AudioFixture.rawFloat32(ToneSynth.majorCadence(root: 48))

    @Test func stdinCadenceGivesOneResultInC() throws {
        let run = try CLIInvocation.run([], stdin: Self.cadence)
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let results = try run.results()
        #expect(results.count == 1)
        #expect(results.first?.key == .c)
    }

    @Test func continuousEmitsOneResultPerHop() throws {
        let run = try CLIInvocation.run(["--continuous"], stdin: Self.cadence)
        #expect(run.status == 0)
        let results = try run.results()
        #expect(results.count > 50)
        let timestamps = results.map(\.timestamp)
        #expect(timestamps == timestamps.sorted())
    }

    @Test func lineFormatHasFourTabSeparatedFields() throws {
        let run = try CLIInvocation.run(["--format", "line"], stdin: Self.cadence)
        #expect(run.status == 0)
        #expect(run.lines.count == 1)
        let fields = run.lines.first?.split(separator: "\t", omittingEmptySubsequences: false) ?? []
        #expect(fields.count == 4)
        #expect(fields.dropFirst().first?.hasPrefix("C ") == true)
    }

    @Test(arguments: [0, 1])
    func alternatesFlagLimitsAlternates(count: Int) throws {
        let run = try CLIInvocation.run(["--alternates", String(count)], stdin: Self.cadence)
        #expect(run.status == 0)
        #expect(try run.results().first?.alternates.count == count)
    }

    @Test func durationStopsEarly() throws {
        let full = try CLIInvocation.run(["--continuous"], stdin: Self.cadence)
        let short = try CLIInvocation.run(["--continuous", "--duration", "1"], stdin: Self.cadence)
        #expect(short.status == 0)
        let shortCount = try short.results().count
        #expect(shortCount > 0)
        #expect(shortCount < (try full.results().count) / 2)
    }

    @Test func emptyStdinExitsThree() throws {
        let run = try CLIInvocation.run([])
        #expect(run.status == 3)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.hasPrefix("mockingbird: error:"))
    }

    @Test func inputShorterThanOneWindowExitsThree() throws {
        let run = try CLIInvocation.run([], stdin: AudioFixture.rawFloat32([Float](repeating: 0.1, count: 4000)))
        #expect(run.status == 3)
        #expect(run.stdout.isEmpty)
    }

    @Test(arguments: [["--window-size", "1000"], ["--frobnicate"], ["--format", "xml"]])
    func usageErrorsExitTwo(arguments: [String]) throws {
        let run = try CLIInvocation.run(arguments, stdin: Self.cadence)
        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.hasPrefix("mockingbird: error:"))
        #expect(run.stderr.contains(arguments[0]))
    }

    @Test(arguments: ["no-such-file.raw", "no-such-file.wav"])
    func missingFileExitsFour(name: String) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("mockingbird-\(UUID())-\(name)").path
        let run = try CLIInvocation.run([path])
        #expect(run.status == 4)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.hasPrefix("mockingbird: error:"))
        #expect(run.stderr.contains(path))
    }

    @Test func malformedProfilesExitsFour() throws {
        let url = try AudioFixture.writeTemporary(Data("{not json".utf8), fileExtension: "json")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try CLIInvocation.run(["--profiles", url.path], stdin: Self.cadence)
        #expect(run.status == 4)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains(url.path))
    }

    @Test func emptyProfileLibraryExitsFour() throws {
        let url = try AudioFixture.writeTemporary(Data(#"{"profiles":[]}"#.utf8), fileExtension: "json")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try CLIInvocation.run(["--profiles", url.path], stdin: Self.cadence)
        #expect(run.status == 4)
    }

    @Test func customProfilesRestrictTheAnswer() throws {
        let wanted = ProfileLibrary.default.profiles.filter {
            $0.category == .major && $0.scaleName == "major" && ($0.root == .c || $0.root == .g)
        }
        try #require(wanted.count == 2)
        let json = try JSONEncoder().encode(ProfileLibrary(profiles: wanted))
        let url = try AudioFixture.writeTemporary(json, fileExtension: "json")
        defer { try? FileManager.default.removeItem(at: url) }

        let run = try CLIInvocation.run(["--profiles", url.path], stdin: Self.cadence)
        #expect(run.status == 0)
        let result = try #require(try run.results().first)
        #expect(result.scaleName == "major")
        #expect([PitchClass.c, .g].contains(result.key))
        #expect(result.alternates.count <= 1)
    }

    @Test func helpListsEveryFlag() throws {
        let run = try CLIInvocation.run(["--help"])
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let flags = [
            "--sample-rate", "--window-size", "--hop-size", "--alternates", "--zero-pad",
            "--profiles", "--device", "--continuous", "--format", "--duration",
            "--list-devices", "--file", "--help", "--version",
        ]
        for flag in flags {
            #expect(run.stdout.contains(flag), "help is missing \(flag)")
        }
    }

    @Test func versionExitsZero() throws {
        let run = try CLIInvocation.run(["--version"])
        #expect(run.status == 0)
        #expect(run.stdout.hasPrefix("mockingbird "))
    }

    @Test(arguments: [false, true])
    func rawFileMatchesStdin(useFileFlag: Bool) throws {
        let url = try AudioFixture.writeTemporary(Self.cadence, fileExtension: "raw")
        defer { try? FileManager.default.removeItem(at: url) }
        let fromFile = try CLIInvocation.run(useFileFlag ? ["--file", url.path] : [url.path])
        let fromStdin = try CLIInvocation.run([], stdin: Self.cadence)
        #expect(fromFile.status == 0)
        let fileResult = try #require(try fromFile.results().first)
        let stdinResult = try #require(try fromStdin.results().first)
        #expect(fileResult.key == stdinResult.key)
        #expect(fileResult.scaleName == stdinResult.scaleName)
        #expect(fileResult.confidence == stdinResult.confidence)
        #expect(fileResult.alternates == stdinResult.alternates)
    }
}
