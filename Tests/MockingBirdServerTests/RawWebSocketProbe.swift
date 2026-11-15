import Foundation
import NIOCore
import NIOPosix

/// A minimal WebSocket reader over a plain TCP channel: sends the upgrade request (and an
/// optional masked text frame), then decodes server frames until a close frame arrives.
///
/// Used for cases where the server fails immediately after the upgrade. HummingbirdWSClient
/// intermittently misses frames that arrive right behind the `101` response (it hung in
/// about one run in three; Python's `websockets` saw the error frame and 1011 in 200/200
/// tries against the same server), so those tests read the wire directly.
enum RawWebSocketProbe {
    struct Outcome: Sendable {
        var upgraded = false
        var texts: [String] = []
        var closeCode: UInt16?
    }

    static func run(port: Int, path: String, sendText: String? = nil) async throws -> Outcome {
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connect(host: "127.0.0.1", port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                }
            }
        return try await channel.executeThenClose { inbound, outbound in
            var request = ByteBuffer(string: """
                GET \(path) HTTP/1.1\r
                Host: 127.0.0.1:\(port)\r
                Upgrade: websocket\r
                Connection: Upgrade\r
                Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
                Sec-WebSocket-Version: 13\r
                \r

                """)
            if let sendText {
                request.writeBytes(maskedTextFrame(sendText))
            }
            try await outbound.write(request)

            var received = [UInt8]()
            var outcome = Outcome()
            for try await chunk in inbound {
                received += chunk.readableBytesView
                outcome = decode(received)
                if outcome.closeCode != nil {
                    break
                }
            }
            return outcome
        }
    }

    private static func maskedTextFrame(_ text: String) -> [UInt8] {
        let payload = Array(text.utf8)
        precondition(payload.count < 126, "probe only sends short frames")
        let mask: [UInt8] = [1, 2, 3, 4]
        return [0x81, 0x80 | UInt8(payload.count)] + mask
            + payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
    }

    /// Decodes the HTTP response head and every complete frame in `bytes`.
    private static func decode(_ bytes: [UInt8]) -> Outcome {
        var outcome = Outcome()
        let separator = Array("\r\n\r\n".utf8)
        guard let headEnd = (0...max(0, bytes.count - 4)).first(where: { Array(bytes[$0..<min($0 + 4, bytes.count)]) == separator }) else {
            return outcome
        }
        outcome.upgraded = String(decoding: bytes[0..<headEnd], as: UTF8.self).hasPrefix("HTTP/1.1 101")
        var index = headEnd + 4
        while index + 2 <= bytes.count {
            let opcode = bytes[index] & 0x0F
            var length = Int(bytes[index + 1] & 0x7F)
            var header = 2
            if length == 126 {
                guard index + 4 <= bytes.count else { break }
                length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
                header = 4
            } else if length == 127 {
                guard index + 10 <= bytes.count else { break }
                length = (2..<10).reduce(0) { $0 << 8 | Int(bytes[index + $1]) }
                header = 10
            }
            guard index + header + length <= bytes.count else { break }
            let payload = Array(bytes[(index + header)..<(index + header + length)])
            switch opcode {
            case 0x1:
                outcome.texts.append(String(decoding: payload, as: UTF8.self))
            case 0x8:
                outcome.closeCode = payload.count >= 2 ? UInt16(payload[0]) << 8 | UInt16(payload[1]) : 1005
            default:
                break
            }
            index += header + length
        }
        return outcome
    }
}
