import Foundation
import Testing
import MockingBirdTestSupport
@testable import MockingBirdCore

@Suite("RawPCMSource")
struct RawPCMSourceTests {
    private static let samples: [Float] = (0..<5000).map { Float(sin(Double($0) * 0.01)) * 0.8 + Float($0 % 7) * 1e-3 }

    private func collect(_ stream: AsyncThrowingStream<[Float], Error>) async throws -> [Float] {
        var all: [Float] = []
        for try await chunk in stream { all += chunk }
        return all
    }

    @Test("samples stay aligned when the pipe delivers odd-sized pieces", arguments: [3, 5, 7])
    func oddSizedWrites(pieceSize: Int) async throws {
        let pipe = Pipe()
        let bytes = AudioFixture.rawFloat32(Self.samples)
        let writer = Task {
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + pieceSize, bytes.count)
                pipe.fileHandleForWriting.write(bytes.subdata(in: offset..<end))
                offset = end
                if offset % (pieceSize * 512) < pieceSize { await Task.yield() }
            }
            try pipe.fileHandleForWriting.close()
        }
        let source = RawPCMSource(handle: pipe.fileHandleForReading, chunkSize: 256)
        let received = try await collect(try source.start(sampleRate: 44100))
        try await writer.value
        #expect(received == Self.samples)
    }

    @Test("decodes little-endian Float32 explicitly")
    func littleEndian() async throws {
        let pipe = Pipe()
        // 1.0 = 0x3F800000, -2.5 = 0xC0200000, little-endian byte order.
        pipe.fileHandleForWriting.write(Data([0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x20, 0xC0]))
        try pipe.fileHandleForWriting.close()
        let received = try await collect(try RawPCMSource(handle: pipe.fileHandleForReading).start(sampleRate: 44100))
        #expect(received == [1.0, -2.5])
    }

    @Test("a trailing partial sample at end of input is dropped")
    func trailingPartialSample() async throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(AudioFixture.rawFloat32([0.25, 0.5]) + Data([0x01, 0x02]))
        try pipe.fileHandleForWriting.close()
        let received = try await collect(try RawPCMSource(handle: pipe.fileHandleForReading).start(sampleRate: 44100))
        #expect(received == [0.25, 0.5])
    }

    @Test("stop() ends the stream")
    func stopEndsStream() async throws {
        let pipe = Pipe()
        let source = RawPCMSource(handle: pipe.fileHandleForReading, chunkSize: 4)
        let stream = try source.start(sampleRate: 44100)
        pipe.fileHandleForWriting.write(AudioFixture.rawFloat32([1, 2, 3, 4]))
        var chunks = 0
        for try await _ in stream {
            chunks += 1
            source.stop()
            // Unblock the pending read so the reader notices the stop.
            pipe.fileHandleForWriting.write(AudioFixture.rawFloat32([5, 6, 7, 8]))
        }
        #expect(chunks == 1)
        try pipe.fileHandleForWriting.close()
    }
}
