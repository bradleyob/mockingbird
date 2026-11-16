import Foundation

/// Maps a `Content-Type` header to an `AudioMediaType` (contract §4.4).
enum AudioMediaTypeResolver {
    private static let encodedExtensions: [String: String] = [
        "audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav",
        "audio/aiff": "aiff", "audio/x-aiff": "aiff",
        "audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a",
        "audio/mpeg": "mp3",
        "audio/flac": "flac",
    ]

    /// - Parameter contentType: The raw header value, e.g. `audio/wav; codecs=1`, or `nil`.
    /// - Throws: `APIError.unsupportedMediaType` for anything not in the contract.
    static func resolve(_ contentType: String?) throws(APIError) -> AudioMediaType {
        let mediaType = (contentType ?? "")
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        switch mediaType {
        case "", "application/octet-stream", "audio/pcm":
            return .rawPCM
        default:
            guard let fileExtension = encodedExtensions[mediaType] else {
                throw APIError.unsupportedMediaType(mediaType)
            }
            return .encoded(fileExtension: fileExtension)
        }
    }
}
