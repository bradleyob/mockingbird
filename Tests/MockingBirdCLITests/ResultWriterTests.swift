import Foundation
@testable import MockingBirdCLI
import Testing

@Suite struct ResultWriterTests {
    @Test func writesEachLineTerminatedByNewline() throws {
        let pipe = Pipe()
        let writer = ResultWriter(handle: pipe.fileHandleForWriting)
        try writer.write(line: "first")
        try writer.write(line: "second")
        try pipe.fileHandleForWriting.close()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == "first\nsecond\n")
    }
}
