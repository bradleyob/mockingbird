import Foundation
import MockingBirdTestSupport
import Testing
@testable import MockingBirdApp

@Suite struct LaunchArgumentsTests {
    @Test func existingFileAsFirstArgumentIsReturned() throws {
        let url = try AudioFixture.writeTemporary(Data([0]), fileExtension: "wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let found = LaunchArguments.fileToAnalyze(in: ["/Applications/MockingBird.app/Contents/MacOS/MockingBird", url.path])
        #expect(found?.standardizedFileURL == url.standardizedFileURL)
    }

    @Test func noArgumentsMeansNoFile() {
        #expect(LaunchArguments.fileToAnalyze(in: ["MockingBird"]) == nil)
        #expect(LaunchArguments.fileToAnalyze(in: []) == nil)
    }

    @Test func missingFileIsIgnored() {
        #expect(LaunchArguments.fileToAnalyze(in: ["MockingBird", "/no/such/file-\(UUID().uuidString).wav"]) == nil)
    }

    @Test func systemFlagsAreNotFiles() {
        #expect(LaunchArguments.fileToAnalyze(in: ["MockingBird", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        #expect(LaunchArguments.fileToAnalyze(in: ["MockingBird", "-psn_0_12345"]) == nil)
    }

    @Test func directoryIsNotAFile() {
        #expect(LaunchArguments.fileToAnalyze(in: ["MockingBird", NSTemporaryDirectory()]) == nil)
    }
}
