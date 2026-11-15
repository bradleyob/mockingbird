import Foundation

/// Splits an asynchronous sequence of byte chunks into UTF-8 lines.
///
/// Lines end at `\n` (a trailing `\r` is dropped); an unterminated last line is emitted at
/// end of input; empty lines are skipped. Needed because `FileHandle.bytes` does not exist
/// in swift-corelibs-foundation.
struct DataLineSequence: AsyncSequence, Sendable {
    typealias Element = String

    let base: AsyncStream<Data>

    struct AsyncIterator: AsyncIteratorProtocol {
        var chunks: AsyncStream<Data>.AsyncIterator
        var pending = Data()
        var finished = false

        mutating func next() async -> String? {
            while true {
                if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    if let text = Self.text(line) {
                        return text
                    }
                    continue
                }
                if finished {
                    let rest = pending
                    pending = Data()
                    return Self.text(rest)
                }
                if let chunk = await chunks.next() {
                    pending.append(chunk)
                } else {
                    finished = true
                }
            }
        }

        private static func text(_ bytes: Data) -> String? {
            var trimmed = bytes
            if trimmed.last == UInt8(ascii: "\r") {
                trimmed.removeLast()
            }
            guard !trimmed.isEmpty else { return nil }
            return String(decoding: trimmed, as: UTF8.self)
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(chunks: base.makeAsyncIterator())
    }
}
