/// How a `POST /analyze` body reaches the CLI.
enum AudioMediaType: Equatable, Sendable {
    /// Mono Float32 little-endian PCM, piped to stdin.
    case rawPCM
    /// An encoded file, staged on disk with this extension and passed as the positional file.
    case encoded(fileExtension: String)
}
