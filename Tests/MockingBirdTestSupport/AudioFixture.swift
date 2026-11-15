import Foundation

/// Serializes test signals into the byte formats the CLI and server accept.
public enum AudioFixture {
    /// Raw mono Float32 little-endian PCM — the `mockingbird` stdin / `.raw` format.
    public static func rawFloat32(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 4)
        for sample in samples {
            withUnsafeBytes(of: sample.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// A canonical 44-byte-header RIFF/WAVE file: mono, 16-bit signed PCM.
    public static func wav16(_ samples: [Float], sampleRate: Int = 44100) -> Data {
        let dataBytes = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                 // fmt chunk size
        append(UInt16(1))                  // PCM
        append(UInt16(1))                  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))     // byte rate
        append(UInt16(2))                  // block align
        append(UInt16(16))                 // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(Int16((clamped * 32767).rounded()))
        }
        return data
    }

    /// Writes `data` to a uniquely named file in the temporary directory and returns its URL.
    /// The caller removes it.
    public static func writeTemporary(_ data: Data, fileExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mockingbird-test-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try data.write(to: url)
        return url
    }
}
