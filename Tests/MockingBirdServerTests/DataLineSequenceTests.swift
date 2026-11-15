import Foundation
import Testing
@testable import MockingBirdServer

@Suite struct DataLineSequenceTests {
    private func lines(_ chunks: [String]) async -> [String] {
        let stream = AsyncStream<Data> { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        }
        var result: [String] = []
        for await line in DataLineSequence(base: stream) {
            result.append(line)
        }
        return result
    }

    @Test func splitsAcrossChunkBoundaries() async {
        #expect(await lines(["{\"a\":", "1}\n{\"b\"", ":2}\n"]) == [#"{"a":1}"#, #"{"b":2}"#])
    }

    @Test func emitsUnterminatedLastLineAndSkipsEmptyLines() async {
        #expect(await lines(["x\n\n", "y\r\n", "z"]) == ["x", "y", "z"])
    }

    @Test func emptyInputHasNoLines() async {
        #expect(await lines([]).isEmpty)
    }
}
